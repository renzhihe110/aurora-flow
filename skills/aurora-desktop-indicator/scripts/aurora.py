#!/usr/bin/env python3
"""Aurora Flow 的会话式启停和 Codex hooks 入口，仅使用 Python 标准库。"""

import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import signal
import subprocess
import sys
import time


# App 随 skill 固定存放，状态文件独立于项目目录及 Codex 聊天记录。
SKILL_DIR = Path(__file__).resolve().parents[1]
APP = SKILL_DIR / 'assets' / 'AuroraFlow.app'
EXECUTABLE = APP / 'Contents' / 'MacOS' / 'AuroraFlow'
# Different installation directories must not overwrite each other's session ownership.
INSTALLATION_KEY = hashlib.sha256(str(SKILL_DIR).encode()).hexdigest()[:12]
RUNTIME = Path.home() / 'Library' / 'Application Support' / 'CodexAurora' / INSTALLATION_KEY
STATE_FILE = RUNTIME / 'state.json'
DESKTOP_NAMES = re.compile(r'(computer[-_]use|agent[-_]desktop|mac[-_]input|cua[-_]repl)', re.I)
NODE_NAMES = re.compile(r'node[-_]repl', re.I)
HOOK_MATCHER = r'(?i)(computer[-_]use|agent[-_]desktop|mac[-_]input|cua[-_]repl|node[-_]repl|^Bash$|exec_command)'


def identity(pid):
    """比较可执行路径和启动时间，防止 PID 复用后误退出其他进程。"""
    if not pid:
        return None
    result = subprocess.run(['/bin/ps', '-ww', '-p', str(pid), '-o', 'lstart=', '-o', 'comm='], capture_output=True, text=True, timeout=0.5)
    line = result.stdout.strip()
    if result.returncode != 0 or not line.endswith(str(EXECUTABLE)):
        return None
    return line


def shell_uses_desktop(command):
    """只识别命令位置，避免 echo、注释或搜索文本提及工具时点亮边框。"""
    lexer = shlex.shlex(command, posix=True, punctuation_chars=';&|\n')
    lexer.whitespace = ' \t\r'
    lexer.whitespace_split = True
    at_command = True
    for token in lexer:
        if token and all(character in ';&|\n' for character in token):
            at_command = True
        elif at_command:
            if token in ('env', 'command', 'exec', 'nohup') or re.match(r'^[A-Za-z_]\w*=', token):
                continue
            at_command = False
            if Path(token).name in ('agent-desktop', 'computer-use', 'mac-input'):
                return True
    return False


def is_desktop_call(payload):
    name = payload.get('tool_name', '')
    arguments = payload.get('tool_input', {})
    if DESKTOP_NAMES.search(name):
        return True
    if not isinstance(arguments, dict):
        return False
    if NODE_NAMES.search(name):
        code = arguments.get('code', '')
        return bool(re.search(r'\b(?:cua|agentDesktop)\s*\.', code))
    if name == 'Bash' or 'exec_command' in name:
        return shell_uses_desktop(arguments.get('command', arguments.get('cmd', '')))
    return False


def launch_app():
    """等 App 建立真实 Overlay 后再返回，启动失败则回收本次创建的进程。"""
    diagnostics = RUNTIME / 'overlay.json'
    stamp = diagnostics.stat().st_mtime_ns if diagnostics.exists() else 0
    process = subprocess.Popen([str(EXECUTABLE), '--start', '--diagnostics', str(diagnostics)], stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
    started = identity(process.pid)
    try:
        if not started:
            raise RuntimeError('无法确认 Aurora Flow 进程身份')
        for attempt in range(40):
            if process.poll() is not None:
                raise RuntimeError('Aurora Flow 在启动期间退出')
            if diagnostics.exists() and diagnostics.stat().st_mtime_ns != stamp:
                report = json.loads(diagnostics.read_text())
                if report.get('state') == 'Running' and not report.get('lastError'):
                    return {'pid': process.pid, 'identity': started}
                raise RuntimeError(report.get('lastError') or 'Aurora Flow 未进入 Running')
            time.sleep(0.03)
        raise RuntimeError('等待 Aurora Flow 初始化超时')
    except Exception:
        if started and identity(process.pid) == started:
            os.kill(process.pid, signal.SIGTERM)
        raise


def change(action, session=None, turn=None, release_all=False):
    """锁内串行管理占用；没有使用者时立即退出，不运行常驻监控。"""
    if action == 'stop' and not STATE_FILE.exists():
        return {'running': False, 'sessions': []}
    RUNTIME.mkdir(parents=True, exist_ok=True)
    with (RUNTIME / 'state.lock').open('a') as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        state = json.loads(STATE_FILE.read_text()) if STATE_FILE.exists() else {}
        current = identity(state.get('pid'))
        if not current or current != state.get('identity'):
            state = {}
        sessions = state.setdefault('sessions', {})
        if action == 'start':
            if not EXECUTABLE.is_file():
                raise RuntimeError('缺少随 skill 携带的 AuroraFlow.app，不自动编译')
            if not state.get('pid'):
                state.update(launch_app())
            sessions[session] = {'turn': turn}
        elif action == 'stop':
            if release_all:
                sessions.clear()
            elif session in sessions:
                previous_turn = sessions[session].get('turn')
                if not turn or not previous_turn or turn == previous_turn:
                    sessions.pop(session)
            if not sessions and state.get('pid'):
                # SIGTERM 让系统关闭全部窗口，只操作这个受管理的可执行实例。
                try:
                    os.kill(state['pid'], signal.SIGTERM)
                except ProcessLookupError:
                    pass
                for attempt in range(25):
                    if identity(state['pid']) != state['identity']:
                        state = {}
                        break
                    time.sleep(0.03)
                else:
                    raise RuntimeError('Aurora Flow 退出超时，请稍后用 stop --all 重试')
        if action != 'status':
            temporary = STATE_FILE.with_suffix('.tmp')
            temporary.write_text(json.dumps(state, ensure_ascii=False))
            temporary.replace(STATE_FILE)
        return {'running': bool(state.get('pid')), 'pid': state.get('pid'), 'sessions': sorted(state.get('sessions', {}))}


def hook(payload):
    """只产生视觉副作用，不放行、拒绝或改写原本的工具调用。"""
    session = payload.get('session_id')
    if not isinstance(session, str) or not session:
        return
    event = payload.get('hook_event_name')
    turn = payload.get('turn_id')
    if event == 'PreToolUse' and is_desktop_call(payload):
        change('start', session, turn)
    elif event == 'PostToolUse':
        arguments = payload.get('tool_input', {})
        if DESKTOP_NAMES.search(payload.get('tool_name', '')) and isinstance(arguments, dict) and 'completion_summary' in arguments:
            change('stop', session, turn)
    elif event in ('Stop', 'Interrupt', 'SessionEnd'):
        change('stop', session, None if event == 'SessionEnd' else turn)


def install_hooks(codex_dir=None):
    """仅合并自己的 hook 定义，保留用户其他配置，不写信任记录。"""
    codex_dir = Path(codex_dir) if codex_dir else Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex')))
    path = codex_dir / 'hooks.json'
    command = shlex.join([sys.executable, str(Path(__file__).resolve()), 'hook'])
    definitions = {}
    for event in ('PreToolUse', 'PostToolUse', 'Stop', 'Interrupt', 'SessionEnd'):
        group = {'hooks': [{'type': 'command', 'command': command, 'timeout': 3}]}
        if event in ('PreToolUse', 'PostToolUse'):
            group['matcher'] = HOOK_MATCHER
        definitions[event] = [group]
    data = json.loads(path.read_text()) if path.exists() else {}
    existing = data.setdefault('hooks', {})
    for event, groups in definitions.items():
        kept = []
        for group in existing.get(event, []):
            handlers = [item for item in group.get('hooks', []) if str(SKILL_DIR / 'scripts' / 'aurora.py') not in item.get('command', '')]
            if handlers:
                kept.append({**group, 'hooks': handlers})
        existing[event] = kept + groups
    if path.exists() and path.read_text() != json.dumps(data, ensure_ascii=False, indent=2) + '\n':
        backup = path.with_name('hooks.before-aurora-' + str(time.time_ns()) + '.json')
        backup.write_bytes(path.read_bytes())
    codex_dir.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    return {'installed': str(path), 'reviewRequired': True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('start', 'stop', 'status', 'hook', 'install-hooks'))
    # 安装器可指定 Codex 配置位置，不覆盖进程已有的 CODEX_HOME。
    parser.add_argument('--codex-dir', type=Path, help='Codex configuration directory for install-hooks')
    parser.add_argument('--session', default=os.environ.get('CODEX_THREAD_ID'))
    parser.add_argument('--all', action='store_true', dest='release_all')
    args = parser.parse_args()
    try:
        if args.action == 'hook':
            hook(json.load(sys.stdin))
            result = {}
        elif args.action == 'install-hooks':
            result = install_hooks(args.codex_dir)
        else:
            if args.action in ('start', 'stop') and not args.session and not args.release_all:
                raise RuntimeError('缺少 CODEX_THREAD_ID，请显式传入 --session 当前聊天ID')
            result = change(args.action, args.session, release_all=args.release_all)
        print(json.dumps(result, ensure_ascii=False))
    except Exception as error:
        if args.action == 'hook':
            # 指示器不可用时让原任务照常继续，不改变工具权限或任务结果。
            print(json.dumps({'systemMessage': 'Aurora 桌面光效不可用：' + str(error)}, ensure_ascii=False))
        else:
            print(json.dumps({'error': str(error)}, ensure_ascii=False), file=sys.stderr)
            return 1
    return 0


if __name__ == '__main__':
    raise SystemExit(main())

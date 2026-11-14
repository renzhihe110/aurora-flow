#!/usr/bin/env python3
"""Install or remove the Aurora desktop indicator skill on macOS."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time


# The release archive and source checkout use the same relocatable skill layout.
NAME = 'aurora-desktop-indicator'
SOURCE = Path(__file__).resolve().parents[1]
BEGIN = '<!-- aurora-desktop-indicator:start -->'
END = '<!-- aurora-desktop-indicator:end -->'


def write_text(path, text):
    """Back up existing user files and replace them atomically."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text() == text:
        return
    if path.exists():
        backup = path.with_name(path.name + '.before-aurora-' + str(time.time_ns()))
        shutil.copy2(path, backup)
    temporary = path.with_name(path.name + '.aurora-tmp')
    temporary.write_text(text)
    temporary.replace(path)


def without_instructions(text):
    """Remove only the block created by this installer."""
    start = text.find(BEGIN)
    finish = text.find(END, start)
    if start >= 0 and finish >= 0:
        return text[:start] + text[finish + len(END):]
    return text


def enable_hooks(codex_dir, destination):
    """Install lifecycle hooks and routing, leaving Codex trust review to the user."""
    controller = destination / 'scripts' / 'aurora.py'
    subprocess.run([sys.executable, str(controller), 'install-hooks', '--codex-dir', str(codex_dir)], check=True)
    agents = codex_dir / 'AGENTS.md'
    existing = agents.read_text() if agents.exists() else ''
    block = f'''{BEGIN}
## Aurora desktop indicator
- Before real desktop operations with computer-use, cua_repl, agent-desktop or mac-input, use the aurora-desktop-indicator skill at `{destination / 'SKILL.md'}`.
- Keep the indicator running across consecutive desktop operations. Release the current session immediately when that phase completes, fails, is cancelled, or hands control to the user. Do not activate it for ordinary coding, computation or discussion of desktop tools.
{END}'''
    write_text(agents, without_instructions(existing).rstrip() + '\n\n' + block + '\n')
    print('Hooks installed. Review and trust them in Codex Settings > Hooks or CLI /hooks.')


def uninstall(codex_dir, destination):
    """Only remove an installer-owned skill and its exact hook commands."""
    marker = destination / '.aurora-install.json'
    if not marker.is_file() or json.loads(marker.read_text()).get('skill') != NAME:
        raise RuntimeError('Destination is not an installer-managed Aurora skill; nothing removed.')
    subprocess.run([sys.executable, str(destination / 'scripts' / 'aurora.py'), 'stop', '--all'], check=True)
    hooks_path = codex_dir / 'hooks.json'
    if hooks_path.exists():
        data = json.loads(hooks_path.read_text())
        for event, groups in list(data.get('hooks', {}).items()):
            kept = []
            for group in groups:
                handlers = [item for item in group.get('hooks', []) if str(destination / 'scripts' / 'aurora.py') not in item.get('command', '')]
                if handlers:
                    kept.append({**group, 'hooks': handlers})
            if kept:
                data['hooks'][event] = kept
            else:
                data['hooks'].pop(event)
        write_text(hooks_path, json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    agents = codex_dir / 'AGENTS.md'
    if agents.exists():
        write_text(agents, without_instructions(agents.read_text()))
    shutil.rmtree(destination)
    print('Removed Aurora skill and its hooks. Existing Codex trust records remain managed by Codex.')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, help='Use an existing AuroraFlow.app instead of the bundled App')
    parser.add_argument('--codex-home', type=Path, default=Path(os.environ.get('CODEX_HOME', str(Path.home() / '.codex'))))
    parser.add_argument('--enable-hooks', action='store_true', help='Also merge hooks.json and add a marked AGENTS.md block')
    parser.add_argument('--replace', action='store_true', help='Replace a previous installer-managed skill')
    parser.add_argument('--uninstall', action='store_true', help='Remove the managed skill and its hook entries')
    args = parser.parse_args()
    try:
        if sys.platform != 'darwin':
            raise RuntimeError('Aurora Flow requires macOS.')
        codex_dir = args.codex_home.expanduser().resolve()
        destination = codex_dir / 'skills' / NAME
        if args.uninstall:
            uninstall(codex_dir, destination)
            return 0
        if destination == SOURCE:
            raise RuntimeError('Run the installer from the extracted archive or source checkout, outside the destination.')
        app = (args.app or SOURCE / 'assets' / 'AuroraFlow.app').expanduser().resolve()
        if not (app / 'Contents' / 'MacOS' / 'AuroraFlow').is_file():
            raise RuntimeError('AuroraFlow.app is missing. Use the complete skill release ZIP or pass --app after building locally.')
        subprocess.run(['/usr/bin/codesign', '--verify', '--deep', '--strict', str(app)], check=True)
        if destination.exists():
            marker = destination / '.aurora-install.json'
            if not args.replace or not marker.is_file() or json.loads(marker.read_text()).get('skill') != NAME:
                raise RuntimeError('Destination exists. --replace only replaces an installer-managed Aurora skill.')
            subprocess.run([sys.executable, str(destination / 'scripts' / 'aurora.py'), 'stop', '--all'], check=True)
        destination.parent.mkdir(parents=True, exist_ok=True)
        # Stage a complete skill before replacing a previously installed version.
        with tempfile.TemporaryDirectory(prefix='.aurora-install-', dir=destination.parent) as temporary:
            staged = Path(temporary) / NAME
            shutil.copytree(SOURCE, staged, ignore=shutil.ignore_patterns('assets', '__pycache__', '*.pyc', '.aurora-install.json'))
            shutil.copytree(app, staged / 'assets' / 'AuroraFlow.app', symlinks=True)
            (staged / '.aurora-install.json').write_text(json.dumps({'skill': NAME, 'format': 1}) + '\n')
            if destination.exists():
                shutil.rmtree(destination)
            staged.rename(destination)
        if args.enable_hooks:
            enable_hooks(codex_dir, destination)
        print('Installed: ' + str(destination))
        print('No App was launched and no source was compiled.')
        return 0
    except Exception as error:
        print('Aurora installation failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())

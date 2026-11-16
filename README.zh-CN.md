# Aurora Flow

原生 macOS 屏幕极光边框，用于提示桌面自动化或后台任务正在执行。

[English](README.md) · [下载发布包](https://github.com/renzhihe110/aurora-flow/releases/latest) · [MIT 许可证](LICENSE)

光效沿系统可用桌面区域四边流动，避开当前菜单栏和 Dock，中心透明、鼠标穿透、不抢占当前应用焦点。四个角均为圆角，默认核心线宽 6 物理像素、光晕半径 40 物理像素、圆角半径 16 物理像素。仓库同时包含 **Swift/AppKit/Metal App** 和支持 `computer-use`、`cua_repl`、`agent-desktop`、`mac-input` 的 **Codex Skill**。

## 下载与要求

| 文件 | 内容 |
| --- | --- |
| `AuroraFlow-1.0.2-macOS-universal.zip` | 独立菜单栏 App，兼容 Apple Silicon 和 Intel |
| `aurora-desktop-indicator-1.0.2.zip` | 完整 Skill、安装器、控制脚本和内置 App |
| `SHA256SUMS.txt` | 两个 ZIP 的 SHA-256 校验值 |

需要 macOS 13+ 和支持 Metal 的 Mac。Skill 还需要 Python 3.9+ 和支持 hooks 的本地 Codex。光效自身不需要屏幕录制或辅助功能权限；桌面操作工具仍遵循各自的权限要求。

预编译 App 使用 ad-hoc 签名，**尚未进行 Developer ID 公证**。macOS 可能要求审核应用后才能运行，也可以从源码本地构建。安装器不会移除隔离属性或绕过 hooks 信任审核。

## 单独使用 App

从 [Releases](https://github.com/renzhihe110/aurora-flow/releases/latest) 下载 App ZIP，解压后将 `AuroraFlow.app` 移动到喜欢的位置并打开。点击菜单栏闪光图标，使用 Start、Success、Error、Stop、Cancel，或调整亮度、粗细、周期、方向和显示器。Quit 完全退出程序。

启动时为 Idle。只有主动打开设置窗口时，该窗口才接收键盘输入；任务状态变化不会激活 App。

参数修改时会自动保存，下次启动时恢复，Skill 和 Hook 启动 App 时同样生效。亮度、线宽、动画周期、方向、显示器选择、光晕半径和圆角半径保存在本机 macOS 偏好设置中（域 `com.auroraflow.demo`，键 `AuroraFlow.config`）。已保存的圆角参数优先于新版默认值。

## 安装 Codex Skill

下载并解压 **完整 Skill ZIP**，在解压目录执行：

```bash
# 安装 Skill，合并 hooks，并添加带标记的全局指令。
python3 aurora-desktop-indicator/scripts/install.py --enable-hooks
```

默认安装到 `${CODEX_HOME:-~/.codex}/skills/aurora-desktop-indicator`。`--enable-hooks` 会合并 Codex 配置目录中的 `hooks.json`，并向 `AGENTS.md` 添加独立标记区块；修改已有文件前创建备份。不会覆盖 MCP、`notify`、审批配置或信任记录。

然后打开 Codex **设置 → Hooks**，或 CLI `/hooks`，审核并信任五项 Aurora hooks，确认它们已启用。客户端未发现变更时可重启或打开新聊天。新定义仍需经过 Codex 正常审核。

不传 `--enable-hooks` 则只安装 Skill，可以在 Codex 中显式调用 `$aurora-desktop-indicator`，由指令控制开始和结束。

```bash
# 指定其他 Codex 配置目录，不覆盖已有环境变量。
python3 aurora-desktop-indicator/scripts/install.py --codex-home /path/to/codex --enable-hooks

# 升级由本安装器安装的版本；不覆盖同名的其他个人 Skill。
python3 aurora-desktop-indicator/scripts/install.py --replace --enable-hooks

# 卸载 Skill、对应 hook 条目和本安装器添加的指令区块。
python3 aurora-desktop-indicator/scripts/install.py --uninstall
```

使用自定义 Codex 目录时，升级和卸载也传相同的 `--codex-home`。安装过程不启动 App、不编译源码。

## 自动启停机制

- `PreToolUse` 识别桌面 MCP/CUA 调用，或 shell 中实际执行的 agent-desktop 命令。
- 第一个聊天启动内置 App，连续操作复用进程；多个聊天可以共享光效。
- CUA 的 `completion_summary` 通过 `PostToolUse` 释放当前聊天。其他工具的桌面操作阶段结束时，由 Skill 指令执行释放。
- `Stop`、`Interrupt`、`SessionEnd` 负责正常结束与中断时兜底；最后一个使用者释放后才退出。
- 退出前核对可执行文件路径、PID 和启动时间，只终止受管理实例。
- 光效失败不会放行、拒绝或改写原桌面操作。不会对每一次点击反复启停。

状态保存在本机 `~/Library/Application Support/CodexAurora/`，没有网络服务、遥测或常驻轮询。若 Codex 被强杀，清理 hooks 可能来不及运行，可手动 `stop --all`。

```bash
# 将 <skill-dir> 替换为安装目录；终端演示时显式指定会话 ID。
python3 '<skill-dir>/scripts/aurora.py' start --session preview
python3 '<skill-dir>/scripts/aurora.py' status
python3 '<skill-dir>/scripts/aurora.py' stop --session preview
```

## 源码构建

用 Xcode 16+ 打开 `AuroraFlow.xcodeproj`，选择 AuroraFlow / My Mac 并 Run。工程文件已提供，不必安装 XcodeGen。本地采用 ad-hoc 签名，无需付费开发者账号。

```bash
# 只有主动执行该命令才进行编译。
xcodebuild -project AuroraFlow.xcodeproj -scheme AuroraFlow -configuration Release -destination 'generic/platform=macOS' -derivedDataPath build CODE_SIGN_IDENTITY=- build

# 给源码中的 Skill 配置刚编译的 App，再安装。
python3 skills/aurora-desktop-indicator/scripts/install.py --app build/Build/Products/Release/AuroraFlow.app --enable-hooks
```

Xcode 提示缺少 Metal Toolchain 时，可在 Settings → Components 安装，或执行 `xcodebuild -downloadComponent MetalToolchain`。

```bash
# 从已有 App 创建两个发布包和校验文件，不触发编译。
python3 scripts/package_release.py --app build/Build/Products/Release/AuroraFlow.app
```

打包器按需用 Apple 工具剥离 Metal 内嵌源码，检查二进制中的个人构建路径，并对发布副本重新 ad-hoc 签名。Git 仅保存源码，包含二进制 App 的完整 Skill 通过 Release ZIP 分发。

## 作为组件接入

将 `AuroraFlow/Core`、`Overlay`、`Rendering` 加入自己的 macOS target，并确认 `.metal` 文件加入 Compile Sources。在主线程使用 `AuroraBorder.start()`、`.success()`、`.error()`、`.cancel()`、`.stop()`；配置赋值即时生效。

尺寸采用物理像素，`cornerRadius` 控制四个角。支持所有屏幕、系统主屏和指定屏幕 UUID。组件本身代表一个任务状态，多任务仲裁由宿主应用决定。

App 还提供 `auroraflow://start`、`success`、`error`、`stop`、`cancel`、`controls`、`configure`。例如 `open -g 'auroraflow://start'` 后台触发效果。URL 的 stop 淡出至 Idle；Skill 最后一次释放则退出整个进程。

## 实现与兼容边界

透明的非激活 AppKit 窗口覆盖完整屏幕，Metal 只着色四周窄边带，时间驱动渐变、呼吸和高光。无截图背景、桌面模糊或全屏模糊 pass。Idle 停止渲染。

标准全屏 Spaces 使用公开 AppKit 行为；锁屏、登录、安全界面、独占显示模式及刘海等物理不可见区域仍受系统控制。多屏与重连逻辑已实现，更多硬件实测见 [验证记录](docs/validation.md)。

[架构与生命周期](docs/architecture.md) · 欢迎提交可复现的问题和改进。本项目独立开发，与 Apple、OpenAI 无隶属关系。

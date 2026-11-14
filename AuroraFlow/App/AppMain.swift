import AppKit

/// 明确入口的主线程隔离，不创建普通主窗口或激活桌面应用。
@main
enum AuroraFlowApplication {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        // NSApplication 弱持有 delegate，明确覆盖整个主事件循环的生命周期。
        withExtendedLifetime(delegate) {
            application.run()
        }
    }
}

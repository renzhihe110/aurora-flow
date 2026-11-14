import AppKit
import Combine
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var controlsPanel: NSPanel?
    private var stateSubscription: AnyCancellable?
    private var diagnosticsURL: URL?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // accessory + LSUIElement 双重保证不占 Dock、不在启动时激活应用。
        NSApp.setActivationPolicy(.accessory)
        let controller = AuroraController.shared
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Aurora Flow")
        item.button?.image?.isTemplate = true
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.toolTip = "Aurora Flow — Idle"
        statusItem = item
        let hosting = NSHostingController(rootView: MenuContentView(controller: controller))
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: hosting.view.fittingSize), styleMask: [.titled, .closable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Aurora Flow Controls"
        panel.contentViewController = hosting
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        controlsPanel = panel
        stateSubscription = controller.$state.sink { [weak self] state in
            self?.statusItem?.button?.toolTip = "Aurora Flow — \(state.rawValue)"
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--diagnostics"), arguments.indices.contains(index + 1) {
            diagnosticsURL = URL(fileURLWithPath: arguments[index + 1])
        }
        if arguments.contains("--start") {
            AuroraBorder.start()
        }
        writeDiagnostics()
    }

    func applicationWillTerminate(_ notification: Notification) {
        AuroraController.shared.shutdown()
        writeDiagnostics()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    /// URL 入口用于后台任务联动；open -g 不切走用户当前应用。
    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme?.lowercased() == "auroraflow" {
            switch url.host?.lowercased() {
            case "start":
                AuroraBorder.start()
            case "stop":
                AuroraBorder.stop()
            case "success":
                AuroraBorder.success()
            case "error":
                AuroraBorder.error()
            case "cancel":
                AuroraBorder.cancel()
            case "controls":
                // 自动隐藏菜单栏时也允许显式打开 Demo 的设置面板。
                togglePopover()
            case "configure":
                applyConfiguration(url)
            case "diagnostics":
                writeDiagnostics()
            default:
                break
            }
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem?.button else {
            return
        }
        guard let panel = controlsPanel else {
            return
        }
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            // 菜单栏拥挤或图标位于刘海附近时，设置窗口仍保持在可见桌面内。
            guard let screen = button.window?.screen ?? NSScreen.screens.first else {
                return
            }
            let visible = screen.visibleFrame.insetBy(dx: 10, dy: 10)
            let anchor = button.window?.convertToScreen(button.convert(button.bounds, to: nil)) ?? visible
            let x = min(max(anchor.midX - panel.frame.width * 0.5, visible.minX), visible.maxX - panel.frame.width)
            panel.setFrameTopLeftPoint(NSPoint(x: x, y: visible.maxY))
            panel.makeKeyAndOrderFront(nil)
        }
    }

    private func applyConfiguration(_ url: URL) {
        var config = AuroraBorder.config
        for item in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
            guard let value = item.value else {
                continue
            }
            switch item.name {
            case "brightness":
                config.brightness = Double(value) ?? config.brightness
            case "borderWidth":
                config.borderWidth = Double(value) ?? config.borderWidth
            case "glowRadius":
                config.glowRadius = Double(value) ?? config.glowRadius
            case "animationDuration":
                config.animationDuration = Double(value) ?? config.animationDuration
            case "breathingDuration":
                config.breathingDuration = Double(value) ?? config.breathingDuration
            case "clockwise":
                config.clockwise = value != "false"
            case "display":
                if value == "all" {
                    config.displayMode = .allScreens
                } else if value == "primary" {
                    config.displayMode = .primaryScreen
                } else {
                    config.displayMode = .screen(value)
                }
            default:
                break
            }
        }
        AuroraBorder.config = config
    }

    private func writeDiagnostics() {
        guard let diagnosticsURL else {
            return
        }
        do {
            let data = try JSONSerialization.data(withJSONObject: AuroraController.shared.diagnostics(), options: [.prettyPrinted, .sortedKeys])
            try data.write(to: diagnosticsURL, options: .atomic)
        } catch {
            NSLog("Aurora diagnostics: %@", error.localizedDescription)
        }
    }
}

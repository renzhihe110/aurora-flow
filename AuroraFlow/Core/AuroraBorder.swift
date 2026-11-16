import AppKit
import Combine
import QuartzCore
import os

/// 在主线程控制 AppKit；后台任务可用 await MainActor.run 调用这些接口。
@MainActor
public enum AuroraBorder {
    public static var config: AuroraConfig {
        get {
            return AuroraController.shared.config
        }
        set {
            AuroraController.shared.update(config: newValue)
        }
    }

    public static var state: AuroraState {
        return AuroraController.shared.state
    }

    public static func start() {
        AuroraController.shared.transition(to: .running)
    }

    public static func stop() {
        AuroraController.shared.transition(to: .stopping)
    }

    public static func success() {
        AuroraController.shared.transition(to: .success)
    }

    public static func error() {
        AuroraController.shared.transition(to: .error)
    }

    public static func cancel() {
        AuroraController.shared.transition(to: .cancelled)
    }
}

@MainActor
final class AuroraController: ObservableObject {
    static let shared = AuroraController()
    @Published private(set) var config: AuroraConfig
    @Published private(set) var state: AuroraState = .idle
    @Published private(set) var displays: [AuroraDisplay] = []
    @Published private(set) var lastError: String?
    private let timeline = AuroraTimeline()
    private let logger = Logger(subsystem: "com.auroraflow.demo", category: "Overlay")
    private var context: AuroraMetalContext?
    private var overlays: [String: AuroraOverlay] = [:]
    private var finishWork: DispatchWorkItem?
    private var appObservers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var displayAsleep = false
    private var sessionInactive = false

    private init() {
        // 从本机设置恢复上次的参数，并在动画启动前同步时间轴。
        let savedConfig = UserDefaults.standard.data(forKey: "AuroraFlow.config").flatMap { try? JSONDecoder().decode(AuroraConfig.self, from: $0) }
        config = (savedConfig ?? AuroraConfig()).sanitized()
        timeline.update(config: config)
        refreshDisplays()
        // 通知仅在拓扑、Space 或系统电源状态改变时触发，Idle 没有轮询。
        observe(NSApplication.didChangeScreenParametersNotification, center: .default) { [weak self] in
            self?.refreshDisplays()
            self?.reconcileOverlays()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        observe(NSWorkspace.activeSpaceDidChangeNotification, center: workspace) { [weak self] in
            self?.reconcileOverlays()
        }
        observe(NSWorkspace.screensDidSleepNotification, center: workspace) { [weak self] in
            self?.displayAsleep = true
            self?.reconcileOverlays()
        }
        observe(NSWorkspace.screensDidWakeNotification, center: workspace) { [weak self] in
            self?.displayAsleep = false
            self?.refreshDisplays()
            self?.reconcileOverlays()
        }
        observe(NSWorkspace.sessionDidResignActiveNotification, center: workspace) { [weak self] in
            self?.sessionInactive = true
            self?.reconcileOverlays()
        }
        observe(NSWorkspace.sessionDidBecomeActiveNotification, center: workspace) { [weak self] in
            self?.sessionInactive = false
            self?.refreshDisplays()
            self?.reconcileOverlays()
        }
    }

    func update(config: AuroraConfig) {
        let sanitized = config.sanitized()
        timeline.update(config: sanitized)
        self.config = sanitized
        // 参数更新时立即保存，确保退出或被 Hook 结束后仍可恢复。
        if let data = try? JSONEncoder().encode(sanitized) {
            UserDefaults.standard.set(data, forKey: "AuroraFlow.config")
        }
        reconcileOverlays()
    }

    func transition(to next: AuroraState) {
        if next == .running && state == .running {
            return
        }
        if (next == .stopping || next == .cancelled) && state == .idle {
            return
        }
        finishWork?.cancel()
        finishWork = nil
        lastError = nil
        let duration = timeline.transition(to: next)
        state = next
        reconcileOverlays()
        logger.info("state=\(self.state.rawValue, privacy: .public) overlays=\(self.overlays.count)")
        if let duration, state != .idle {
            let work = DispatchWorkItem { [weak self] in
                self?.finish()
            }
            finishWork = work
            // common mode 继续渲染菜单操作，单次结束回调不依赖某个屏幕是否仍连接。
            DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
        }
    }

    func shutdown() {
        finishWork?.cancel()
        finishWork = nil
        finish()
        appObservers.forEach { NotificationCenter.default.removeObserver($0) }
        workspaceObservers.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        appObservers.removeAll()
        workspaceObservers.removeAll()
    }

    /// 可选诊断只在显式请求时生成，无屏幕捕获、事件监听或持续采样。
    func diagnostics() -> [String: Any] {
        let panels: [[String: Any]] = overlays.map { id, overlay in
            let start = overlay.renderer.firstFrameTime ?? 0
            let end = overlay.renderer.lastFrameTime ?? 0
            let frames = overlay.renderer.submittedFrames
            return ["displayUUID": id, "frame": NSStringFromRect(overlay.panel.frame), "drawableWidth": overlay.view.drawableSize.width, "drawableHeight": overlay.view.drawableSize.height, "level": overlay.panel.level.rawValue, "ignoresMouseEvents": overlay.panel.ignoresMouseEvents, "canBecomeKey": overlay.panel.canBecomeKey, "canBecomeMain": overlay.panel.canBecomeMain, "isOpaque": overlay.panel.isOpaque, "hasShadow": overlay.panel.hasShadow, "visible": overlay.panel.isVisible, "paused": overlay.view.isPaused, "requestedFPS": overlay.view.preferredFramesPerSecond, "submittedFrames": frames, "averageSubmissionFPS": end > start && frames > 1 ? Double(frames - 1) / (end - start) : 0]
        }
        return ["state": state.rawValue, "overlayCount": overlays.count, "appIsActive": NSApp.isActive, "keyWindow": NSApp.keyWindow?.title ?? "none", "frontmostBundleID": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown", "displayCount": displays.count, "panels": panels, "lastError": lastError ?? NSNull()]
    }

    private func finish() {
        timeline.transition(to: .idle)
        state = .idle
        overlays.values.forEach { $0.close() }
        overlays.removeAll()
        finishWork = nil
        logger.info("state=Idle overlays=0 rendering=stopped")
    }

    private func refreshDisplays() {
        displays = NSScreen.screens.compactMap { screen in
            guard let id = screen.auroraUUID else {
                return nil
            }
            return AuroraDisplay(id: id, name: screen.localizedName, frame: screen.frame, scale: screen.backingScaleFactor, maximumFramesPerSecond: screen.maximumFramesPerSecond)
        }
    }

    private func targetScreens() -> [NSScreen] {
        switch config.displayMode {
        case .allScreens:
            return NSScreen.screens
        case .primaryScreen:
            // screens.first 是菜单栏所在主屏；NSScreen.main 会随键盘焦点改变。
            return Array(NSScreen.screens.prefix(1))
        case .screen(let id):
            return NSScreen.screens.filter { $0.auroraUUID == id }
        }
    }

    private func reconcileOverlays() {
        guard timeline.isActive else {
            return
        }
        let targets = targetScreens()
        let ids = Set(targets.compactMap(\.auroraUUID))
        for id in Array(overlays.keys) where !ids.contains(id) {
            overlays.removeValue(forKey: id)?.close()
        }
        if displayAsleep || sessionInactive {
            overlays.values.forEach { $0.suspend() }
            return
        }
        do {
            if context == nil && !targets.isEmpty {
                context = try AuroraMetalContext()
            }
            guard let context else {
                return
            }
            for screen in targets {
                guard let id = screen.auroraUUID else {
                    continue
                }
                let overlay: AuroraOverlay
                if let existing = overlays[id] {
                    overlay = existing
                    overlay.update(screen: screen, config: config)
                } else {
                    overlay = AuroraOverlay(screen: screen, context: context, timeline: timeline, config: config)
                    overlay.renderer.onFailure = { [weak self] message in
                        self?.fail(message)
                    }
                    overlays[id] = overlay
                }
                overlay.show()
            }
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        finishWork?.cancel()
        finish()
        lastError = message
        logger.error("\(message, privacy: .public)")
    }

    private func observe(_ name: Notification.Name, center: NotificationCenter, action: @escaping @MainActor @Sendable () -> Void) {
        let observer = center.addObserver(forName: name, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                action()
            }
        }
        if center === NotificationCenter.default {
            appObservers.append(observer)
        } else {
            workspaceObservers.append(observer)
        }
    }
}

import AppKit
import MetalKit

/// 此面板永远不成为 key/main window，菜单栏面板也不借用它接收输入。
@MainActor
final class AuroraOverlayPanel: NSPanel {
    override var canBecomeKey: Bool {
        return false
    }

    override var canBecomeMain: Bool {
        return false
    }

    /// 屏幕 Overlay 不应被普通窗口的菜单栏避让规则向下挪动。
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    init(screen: NSScreen) {
        super.init(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        title = "Aurora Flow Overlay"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        acceptsMouseMovedEvents = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        isExcludedFromWindowsMenu = true
        // 高于普通菜单栏和 Dock；锁屏/系统安全界面仍由系统掌控。
        level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.screenSaverWindow)))
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        setFrame(screen.frame, display: false)
    }
}

@MainActor
final class AuroraOverlay {
    let panel: AuroraOverlayPanel
    let view: AuroraMetalView
    let renderer: AuroraRenderer

    init(screen: NSScreen, context: AuroraMetalContext, timeline: AuroraTimeline, config: AuroraConfig) {
        panel = AuroraOverlayPanel(screen: screen)
        view = AuroraMetalView(frame: NSRect(origin: .zero, size: screen.frame.size), device: context.device)
        renderer = AuroraRenderer(context: context, timeline: timeline, config: config)
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        view.autoResizeDrawable = true
        view.autoresizingMask = [.width, .height]
        view.colorPixelFormat = .bgra8Unorm
        view.clearColor = MTLClearColorMake(0, 0, 0, 0)
        view.framebufferOnly = true
        view.delegate = renderer
        panel.contentView = view
        // MTKView 的透明背景和 CAMetalLayer 都必须保留 alpha。
        view.wantsLayer = true
        view.layer?.isOpaque = false
        update(screen: screen, config: config)
    }

    func update(screen: NSScreen, config: AuroraConfig) {
        renderer.config = config
        panel.setFrame(screen.frame, display: false)
        view.drawableSize = CGSize(width: screen.frame.width * screen.backingScaleFactor, height: screen.frame.height * screen.backingScaleFactor)
        view.layer?.contentsScale = screen.backingScaleFactor
        view.preferredFramesPerSecond = max(60, screen.maximumFramesPerSecond)
    }

    func show() {
        // 直接排序窗口，不使用 makeKeyAndOrderFront 或 NSApp.activate。
        panel.orderFrontRegardless()
        view.isPaused = false
    }

    func suspend() {
        view.isPaused = true
        panel.orderOut(nil)
    }

    func close() {
        view.isPaused = true
        view.delegate = nil
        panel.orderOut(nil)
        panel.close()
        view.releaseDrawables()
    }
}

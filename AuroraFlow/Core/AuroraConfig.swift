import AppKit
import CoreGraphics

/// 使用显示器 UUID 标识单屏目标，断开后保留选择，重连时自动恢复。
public enum AuroraDisplayMode: Equatable, Sendable {
    case allScreens
    case primaryScreen
    case screen(String)
}

/// 光线尺寸使用物理像素，窗口尺寸始终由 AppKit 以 point 管理。
public struct AuroraConfig: Equatable, Sendable {
    public var borderWidth: Double
    public var glowRadius: Double
    public var animationDuration: Double
    public var breathingDuration: Double
    public var brightness: Double
    public var clockwise: Bool
    public var displayMode: AuroraDisplayMode
    /// 顶部两个角的圆角半径；底部两个角固定为直角。
    public var cornerRadius: Double

    public init(borderWidth: Double = 3, glowRadius: Double = 24, animationDuration: Double = 8, breathingDuration: Double = 3, brightness: Double = 0.85, clockwise: Bool = true, displayMode: AuroraDisplayMode = .allScreens, cornerRadius: Double = 32) {
        self.borderWidth = borderWidth
        self.glowRadius = glowRadius
        self.animationDuration = animationDuration
        self.breathingDuration = breathingDuration
        self.brightness = brightness
        self.clockwise = clockwise
        self.displayMode = displayMode
        self.cornerRadius = cornerRadius
    }

    /// 限制无效值，避免调用方传入 NaN、零周期或超大绘制区域。
    func sanitized() -> AuroraConfig {
        var result = self
        result.borderWidth = finiteClamp(borderWidth, fallback: 3, range: 1...8)
        result.glowRadius = finiteClamp(glowRadius, fallback: 24, range: 12...60)
        result.animationDuration = finiteClamp(animationDuration, fallback: 8, range: 2...30)
        result.breathingDuration = finiteClamp(breathingDuration, fallback: 3, range: 0.5...12)
        result.brightness = finiteClamp(brightness, fallback: 0.85, range: 0...1)
        result.cornerRadius = finiteClamp(cornerRadius, fallback: 32, range: 4...100)
        return result
    }

    private func finiteClamp(_ value: Double, fallback: Double, range: ClosedRange<Double>) -> Double {
        return value.isFinite ? min(max(value, range.lowerBound), range.upperBound) : fallback
    }
}

/// 屏幕列表供菜单栏和嵌入应用使用；frame 可以包含负坐标。
public struct AuroraDisplay: Identifiable, Equatable {
    public let id: String
    public let name: String
    public let frame: CGRect
    public let scale: CGFloat
    public let maximumFramesPerSecond: Int
}

extension NSScreen {
    var auroraDisplayID: CGDirectDisplayID? {
        return (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    var auroraUUID: String? {
        guard let displayID = auroraDisplayID, let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String
    }
}

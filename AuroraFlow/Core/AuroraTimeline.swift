import QuartzCore
import simd

public enum AuroraState: String, Sendable {
    case idle = "Idle"
    case running = "Running"
    case success = "Success"
    case error = "Error"
    case cancelled = "Cancelled"
    case stopping = "Stopping"
}

/// 所有屏幕共用单调时钟与相位，配置热更新不会让渐变突然回到起点。
struct AuroraVisual {
    var opacity: Float = 0
    var tint = SIMD3<Float>(0, 0, 0)
    var tintAmount: Float = 0
    var emphasis: Float = 0
}

@MainActor
final class AuroraTimeline {
    private(set) var state: AuroraState = .idle
    private var transitionStart = CACurrentMediaTime()
    private var transitionFrom = AuroraVisual()
    private var phaseStart = CACurrentMediaTime()
    private var flowOffset: Double = 0
    private var energyOffset: Double = 0.16
    private var breathOffset: Double = 0
    private var config = AuroraConfig()

    var isActive: Bool {
        return state != .idle
    }

    /// 返回本次终态的总时长，调用方只安排一次结束回调，无常驻状态轮询。
    @discardableResult
    func transition(to state: AuroraState, at now: CFTimeInterval = CACurrentMediaTime()) -> TimeInterval? {
        if state == .running && self.state == .running {
            return nil
        }
        transitionFrom = visual(at: now)
        transitionStart = now
        self.state = state
        switch state {
        case .success:
            return 0.95
        case .error:
            return 1.65
        case .cancelled, .stopping:
            return 0.45
        case .idle, .running:
            return nil
        }
    }

    func update(config: AuroraConfig, at now: CFTimeInterval = CACurrentMediaTime()) {
        let phases = phases(at: now)
        flowOffset = phases.flow
        energyOffset = phases.energy
        breathOffset = phases.breath
        phaseStart = now
        self.config = config
    }

    func phases(at now: CFTimeInterval) -> (flow: Double, energy: Double, breath: Double) {
        let elapsed = now - phaseStart
        let direction: Double = config.clockwise ? 1 : -1
        return (wrap(flowOffset + direction * elapsed / config.animationDuration), wrap(energyOffset + direction * elapsed / (config.animationDuration * 1.4)), wrap(breathOffset + elapsed / config.breathingDuration))
    }

    /// 淡出保留当前色彩，重新 Start 则从当前可见样式连续过渡。
    func visual(at now: CFTimeInterval) -> AuroraVisual {
        let elapsed = max(0, now - transitionStart)
        var result = transitionFrom
        switch state {
        case .idle:
            return AuroraVisual()
        case .running:
            result.opacity = mix(transitionFrom.opacity, 1, ease(elapsed / 0.4))
            result.tintAmount = mix(transitionFrom.tintAmount, 0, ease(elapsed / 0.3))
            result.emphasis = mix(transitionFrom.emphasis, 0, ease(elapsed / 0.3))
        case .success, .error:
            let tintProgress = ease(elapsed / 0.18)
            let target = state == .success ? SIMD3<Float>(0.28, 1, 0.78) : SIMD3<Float>(1, 0.22, 0.16)
            result.tint = transitionFrom.tintAmount > 0 ? simd_mix(transitionFrom.tint, target, SIMD3<Float>(repeating: tintProgress)) : target
            result.tintAmount = mix(transitionFrom.tintAmount, 1, tintProgress)
            let appearance = mix(transitionFrom.opacity, 1, ease(elapsed / 0.12))
            if state == .success {
                result.opacity = appearance * (1 - ease((elapsed - 0.15) / 0.8))
                result.emphasis = 0.24 * Float(sin(.pi * min(elapsed / 0.4, 1)))
            } else {
                // 两个平滑脉冲后才淡出，不使用开关式闪烁。
                let pulseTime = min(elapsed / 1.1, 1)
                let pulse = Float(pow(sin(2 * .pi * pulseTime), 2))
                result.opacity = appearance * (1 - ease((elapsed - 1.1) / 0.55))
                result.emphasis = 0.28 * pulse
            }
        case .cancelled, .stopping:
            result.opacity = transitionFrom.opacity * (1 - ease(elapsed / 0.45))
        }
        return result
    }

    private func ease(_ value: Double) -> Float {
        let t = min(max(value, 0), 1)
        return Float(t * t * (3 - 2 * t))
    }

    private func mix(_ a: Float, _ b: Float, _ t: Float) -> Float {
        return a + (b - a) * t
    }

    private func wrap(_ value: Double) -> Double {
        return value - floor(value)
    }
}

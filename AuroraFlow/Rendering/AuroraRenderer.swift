import AppKit
import MetalKit
import QuartzCore
import simd

/// 一次创建并复用管线，所有显示器共享 GPU 资源和命令队列。
final class AuroraMetalContext {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState

    init() throws {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else {
            throw NSError(domain: "AuroraFlow", code: 1, userInfo: [NSLocalizedDescriptionKey: "此 Mac 无法创建 Metal 设备或命令队列。"])
        }
        guard let library = device.makeDefaultLibrary(), let vertex = library.makeFunction(name: "auroraVertex"), let fragment = library.makeFunction(name: "auroraFragment") else {
            throw NSError(domain: "AuroraFlow", code: 2, userInfo: [NSLocalizedDescriptionKey: "找不到 Aurora Metal Shader，请确认 .metal 文件加入了 App target。"])
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Aurora premultiplied border"
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        // 每个像素只写一次，直接输出预乘透明颜色，无需额外的混合 pass。
        descriptor.colorAttachments[0].isBlendingEnabled = false
        self.device = device
        self.queue = queue
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
}

/// 固定 80 字节的参数，不在 CPU 逐帧构造路径、颜色数组或纹理。
struct AuroraUniforms {
    var geometry: SIMD4<Float>
    var style: SIMD4<Float>
    var animation: SIMD4<Float>
    var feedback: SIMD4<Float>
    var emphasis: SIMD4<Float>
}

@MainActor
final class AuroraMetalView: MTKView {
    override var isOpaque: Bool {
        return false
    }
}

@MainActor
final class AuroraRenderer: NSObject, MTKViewDelegate {
    private let context: AuroraMetalContext
    private let timeline: AuroraTimeline
    private let inFlight = DispatchSemaphore(value: 3)
    var config: AuroraConfig
    private(set) var submittedFrames: UInt64 = 0
    private(set) var firstFrameTime: CFTimeInterval?
    private(set) var lastFrameTime: CFTimeInterval?
    var onFailure: ((String) -> Void)?

    init(context: AuroraMetalContext, timeline: AuroraTimeline, config: AuroraConfig) {
        self.context = context
        self.timeline = timeline
        self.config = config
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // 所有几何量由 drawableSize 驱动，缩放/分辨率变化无需重建路径。
    }

    func draw(in view: MTKView) {
        guard view.drawableSize.width > 1, view.drawableSize.height > 1, inFlight.wait(timeout: .now()) == .success else {
            return
        }
        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable, let command = context.queue.makeCommandBuffer(), let encoder = command.makeRenderCommandEncoder(descriptor: pass) else {
            inFlight.signal()
            return
        }
        let now = CACurrentMediaTime()
        let visual = timeline.visual(at: now)
        let phase = timeline.phases(at: now)
        let radius = Float(config.cornerRadius)
        let width = Float(config.borderWidth)
        let glow = Float(config.glowRadius)
        var uniforms = AuroraUniforms(
            geometry: SIMD4(Float(view.drawableSize.width), Float(view.drawableSize.height), radius, width),
            style: SIMD4(glow, Float(config.brightness), 0, 0),
            animation: SIMD4(Float(phase.flow), Float(0.875 - 0.125 * cos(2 * .pi * phase.breath)), Float(phase.energy), visual.opacity),
            feedback: SIMD4(visual.tint.x, visual.tint.y, visual.tint.z, visual.tintAmount),
            emphasis: SIMD4(visual.emphasis, radius + glow + width + 2, width * 0.5 + 0.5, 0)
        )
        command.label = "Aurora edge frame"
        encoder.setRenderPipelineState(context.pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<AuroraUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<AuroraUniforms>.stride, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 24)
        encoder.endEncoding()
        let semaphore = inFlight
        command.addCompletedHandler { [weak self] completed in
            semaphore.signal()
            if completed.status == .error {
                let message = completed.error?.localizedDescription ?? "Metal 命令执行失败。"
                Task { @MainActor [weak self] in
                    self?.onFailure?(message)
                }
            }
        }
        command.present(drawable)
        command.commit()
        submittedFrames += 1
        firstFrameTime = firstFrameTime ?? now
        lastFrameTime = now
    }
}

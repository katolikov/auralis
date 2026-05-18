import Metal
import MetalKit
import QuartzCore
import simd

struct BackgroundUniforms {
    var time: Float
    var level: Float
    var aspect: Float
    var beat: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var bpm: Float
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
    var features: AudioFeatures = .silent
    var smoothedLevel: Float = 0
    var smoothedLow: Float = 0
    var smoothedMid: Float = 0
    var smoothedHigh: Float = 0
    var smoothedBeat: Float = 0

    private var device: (any MTLDevice)!
    private var commandQueue: (any MTLCommandQueue)!
    private var pipeline: (any MTLRenderPipelineState)!
    private var magnitudesBuffer: (any MTLBuffer)?
    private let magnitudesCapacity = AudioFeatures.binCount

    private let startTime: CFTimeInterval = CACurrentMediaTime()
    private var viewportAspect: Float = 16.0 / 10.0

    func configure(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available on this system.")
        }
        view.device = device
        self.device = device
        self.commandQueue = device.makeCommandQueue()
        buildPipeline(for: view.colorPixelFormat)

        let stride = MemoryLayout<Float>.stride * magnitudesCapacity
        magnitudesBuffer = device.makeBuffer(length: stride, options: .storageModeShared)
        magnitudesBuffer?.label = "Audio magnitudes"
    }

    private func buildPipeline(for format: MTLPixelFormat) {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Could not load default Metal library.")
        }
        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Background"
        desc.vertexFunction = library.makeFunction(name: "background_vertex")
        desc.fragmentFunction = library.makeFunction(name: "background_fragment")
        desc.colorAttachments[0].pixelFormat = format
        do {
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            fatalError("Pipeline failure: \(error)")
        }
    }

    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        let aspect: Float = size.height > 0 ? Float(size.width / size.height) : 1
        Task { @MainActor [weak self] in
            self?.viewportAspect = aspect
        }
    }

    nonisolated func draw(in view: MTKView) {
        Task { @MainActor [weak self] in
            self?.drawOnMain(view: view)
        }
    }

    private func drawOnMain(view: MTKView) {
        guard let drawable = view.currentDrawable,
              let descriptor = view.currentRenderPassDescriptor,
              let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }

        if let buffer = magnitudesBuffer {
            let count = min(features.magnitudes.count, magnitudesCapacity)
            features.magnitudes.withUnsafeBufferPointer { src in
                _ = memcpy(buffer.contents(),
                           src.baseAddress!,
                           count * MemoryLayout<Float>.stride)
            }
        }

        var uniforms = BackgroundUniforms(
            time: Float(CACurrentMediaTime() - startTime),
            level: smoothedLevel,
            aspect: viewportAspect,
            beat: smoothedBeat,
            lowBand: smoothedLow,
            midBand: smoothedMid,
            highBand: smoothedHigh,
            bpm: features.bpm
        )

        encoder.label = "Background pass"
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&uniforms, length: MemoryLayout<BackgroundUniforms>.stride, index: 0)
        if let buffer = magnitudesBuffer {
            encoder.setFragmentBuffer(buffer, offset: 0, index: 1)
        }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()

        command.present(drawable)
        command.commit()
    }
}

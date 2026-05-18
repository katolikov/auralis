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

struct PaletteUniforms {
    var primary: SIMD4<Float>
    var secondary: SIMD4<Float>
    var accent: SIMD4<Float>
    var background: SIMD4<Float>
}

@MainActor
final class Renderer: NSObject, MTKViewDelegate {
    var features: AudioFeatures = .silent
    var smoothed: SmoothedFeatures = SmoothedFeatures(
        level: 0, loudness: 0, low: 0, mid: 0, high: 0, beat: 0
    )
    var palette: Theme.Snapshot = Theme.defaultSnapshot
    var activeMode: VisualizerID = .aurora

    private var device: (any MTLDevice)!
    private var commandQueue: (any MTLCommandQueue)!
    private var magnitudesBuffer: (any MTLBuffer)?
    private var modes: [VisualizerID: any VisualizerMode] = [:]

    private let startTime: CFTimeInterval = CACurrentMediaTime()
    private var viewportAspect: Float = 16.0 / 10.0

    func configure(view: MTKView) {
        guard let device = view.device ?? MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not available on this system.")
        }
        view.device = device
        self.device = device
        self.commandQueue = device.makeCommandQueue()

        let stride = MemoryLayout<Float>.stride * AudioFeatures.binCount
        let buffer = device.makeBuffer(length: stride, options: .storageModeShared)
        buffer?.label = "Magnitudes"
        self.magnitudesBuffer = buffer

        do {
            try registerModes(format: view.colorPixelFormat)
        } catch {
            fatalError("Failed to build visualizer modes: \(error)")
        }
    }

    private func registerModes(format: MTLPixelFormat) throws {
        modes[.aurora]   = try AuroraVisualizer(device: device, format: format)
        modes[.bloom]    = try BloomVisualizer(device: device, format: format)
        modes[.lattice]  = try LatticeVisualizer(device: device, format: format)
        modes[.filament] = try FilamentVisualizer(device: device, format: format)
        modes[.halo]     = try HaloVisualizer(device: device, format: format)
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
              let magnitudesBuffer else { return }

        // Upload magnitudes buffer for the frame.
        let count = min(features.magnitudes.count, AudioFeatures.binCount)
        features.magnitudes.withUnsafeBufferPointer { src in
            _ = memcpy(magnitudesBuffer.contents(),
                       src.baseAddress!,
                       count * MemoryLayout<Float>.stride)
        }

        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].storeAction = .store
        let bg = palette.background
        descriptor.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(bg.x),
            green: Double(bg.y),
            blue: Double(bg.z),
            alpha: 1
        )

        guard let encoder = command.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.label = "Auralis"

        let frame = VisualizerFrame(
            time: Float(CACurrentMediaTime() - startTime),
            aspect: viewportAspect,
            features: features,
            smoothed: smoothed,
            palette: palette,
            magnitudesBuffer: magnitudesBuffer
        )

        let mode = modes[activeMode] ?? modes[.aurora]
        mode?.encode(into: encoder, frame: frame)

        encoder.endEncoding()
        command.present(drawable)
        command.commit()
    }
}

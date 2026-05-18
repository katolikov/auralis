import Foundation
import Metal
import simd

struct HaloUniforms {
    var time: Float
    var aspect: Float
    var loudness: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var beat: Float
    var level: Float
}

@MainActor
final class HaloVisualizer: VisualizerMode {
    static let id: VisualizerID = .halo

    private let pipeline: any MTLRenderPipelineState

    init(device: any MTLDevice, format: MTLPixelFormat) throws {
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.missingLibrary
        }
        guard let vfn = library.makeFunction(name: "fullscreen_vertex"),
              let ffn = library.makeFunction(name: "halo_fragment") else {
            throw RendererError.missingFunction("halo shaders")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Halo"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        desc.colorAttachments[0].pixelFormat = format
        self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame) {
        var u = HaloUniforms(
            time: frame.time,
            aspect: frame.aspect,
            loudness: frame.smoothed.loudness,
            lowBand: frame.smoothed.low,
            midBand: frame.smoothed.mid,
            highBand: frame.smoothed.high,
            beat: frame.smoothed.beat,
            level: frame.smoothed.level
        )
        var palette = PaletteUniforms(
            primary: SIMD4(frame.palette.primary, 1),
            secondary: SIMD4(frame.palette.secondary, 1),
            accent: SIMD4(frame.palette.accent, 1),
            background: SIMD4(frame.palette.background, 1)
        )

        encoder.label = "Halo"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<HaloUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&palette,
                                  length: MemoryLayout<PaletteUniforms>.stride,
                                  index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

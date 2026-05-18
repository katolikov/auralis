import Foundation
import Metal
import simd

struct BloomUniforms {
    var time: Float
    var aspect: Float
    var level: Float
    var loudness: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var beat: Float
}

@MainActor
final class BloomVisualizer: VisualizerMode {
    static let id: VisualizerID = .bloom

    private let background: BackgroundPass
    private let pipeline: any MTLRenderPipelineState

    init(device: any MTLDevice, format: MTLPixelFormat) throws {
        self.background = try BackgroundPass(device: device, format: format)

        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.missingLibrary
        }
        guard let vfn = library.makeFunction(name: "fullscreen_vertex"),
              let ffn = library.makeFunction(name: "bloom_fragment") else {
            throw RendererError.missingFunction("bloom shaders")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Bloom"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        let attach = desc.colorAttachments[0]!
        attach.pixelFormat = format
        attach.isBlendingEnabled = true
        attach.rgbBlendOperation = .add
        attach.alphaBlendOperation = .add
        attach.sourceRGBBlendFactor = .sourceAlpha
        attach.sourceAlphaBlendFactor = .one
        attach.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attach.destinationAlphaBlendFactor = .oneMinusSourceAlpha

        self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame) {
        background.encode(into: encoder, frame: frame)

        var u = BloomUniforms(
            time: frame.time,
            aspect: frame.aspect,
            level: frame.smoothed.level,
            loudness: frame.smoothed.loudness,
            lowBand: frame.smoothed.low,
            midBand: frame.smoothed.mid,
            highBand: frame.smoothed.high,
            beat: frame.smoothed.beat
        )
        var palette = PaletteUniforms(
            primary: SIMD4(frame.palette.primary, 1),
            secondary: SIMD4(frame.palette.secondary, 1),
            accent: SIMD4(frame.palette.accent, 1),
            background: SIMD4(frame.palette.background, 1)
        )

        encoder.label = "Bloom"
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(&u, length: MemoryLayout<BloomUniforms>.stride, index: 0)
        encoder.setFragmentBuffer(frame.magnitudesBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&palette,
                                  length: MemoryLayout<PaletteUniforms>.stride,
                                  index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

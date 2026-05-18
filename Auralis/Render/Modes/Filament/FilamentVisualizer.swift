import Foundation
import Metal
import simd

struct FilamentUniforms {
    var time: Float
    var aspect: Float
    var level: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var beat: Float
    var loudness: Float
    var particleCount: UInt32
    var flowStrength: Float
    var pointSize: Float
    var lifetime: Float
}

@MainActor
final class FilamentVisualizer: VisualizerMode {
    static let id: VisualizerID = .filament

    private let background: BackgroundPass
    private let pipeline: any MTLRenderPipelineState
    private let particleCount: UInt32 = 80_000

    init(device: any MTLDevice, format: MTLPixelFormat) throws {
        self.background = try BackgroundPass(device: device, format: format)

        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.missingLibrary
        }
        guard let vfn = library.makeFunction(name: "filament_vertex"),
              let ffn = library.makeFunction(name: "filament_fragment") else {
            throw RendererError.missingFunction("filament shaders")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Filament"
        desc.vertexFunction = vfn
        desc.fragmentFunction = ffn
        let attach = desc.colorAttachments[0]!
        attach.pixelFormat = format
        attach.isBlendingEnabled = true
        attach.rgbBlendOperation = .add
        attach.alphaBlendOperation = .add
        attach.sourceRGBBlendFactor = .sourceAlpha
        attach.sourceAlphaBlendFactor = .one
        attach.destinationRGBBlendFactor = .one
        attach.destinationAlphaBlendFactor = .one

        self.pipeline = try device.makeRenderPipelineState(descriptor: desc)
    }

    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame) {
        background.encode(into: encoder, frame: frame)

        var u = FilamentUniforms(
            time: frame.time,
            aspect: frame.aspect,
            level: frame.smoothed.level,
            lowBand: frame.smoothed.low,
            midBand: frame.smoothed.mid,
            highBand: frame.smoothed.high,
            beat: frame.smoothed.beat,
            loudness: frame.smoothed.loudness,
            particleCount: particleCount,
            flowStrength: 0.45 + frame.smoothed.high * 6.0,
            pointSize: 2.4,
            lifetime: 3.4
        )
        var palette = PaletteUniforms(
            primary: SIMD4(frame.palette.primary, 1),
            secondary: SIMD4(frame.palette.secondary, 1),
            accent: SIMD4(frame.palette.accent, 1),
            background: SIMD4(frame.palette.background, 1)
        )

        encoder.label = "Filament"
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&u, length: MemoryLayout<FilamentUniforms>.stride, index: 0)
        encoder.setVertexBytes(&palette,
                                length: MemoryLayout<PaletteUniforms>.stride,
                                index: 2)
        encoder.setFragmentBytes(&u, length: MemoryLayout<FilamentUniforms>.stride, index: 0)
        encoder.setFragmentBytes(&palette,
                                  length: MemoryLayout<PaletteUniforms>.stride,
                                  index: 2)
        encoder.drawPrimitives(type: .point,
                               vertexStart: 0,
                               vertexCount: Int(particleCount))
    }
}

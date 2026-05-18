import Foundation
import Metal
import simd

/// Shared fullscreen-triangle background pass. Each visualizer mode may
/// choose to invoke it as the first encode step to lay down a palette-
/// tinted gradient + halo before drawing its own foreground.
@MainActor
final class BackgroundPass {
    let device: any MTLDevice
    private let pipeline: any MTLRenderPipelineState

    init(device: any MTLDevice, format: MTLPixelFormat) throws {
        self.device = device
        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.missingLibrary
        }
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Background"
        descriptor.vertexFunction = library.makeFunction(name: "background_vertex")
        descriptor.fragmentFunction = library.makeFunction(name: "background_fragment")
        descriptor.colorAttachments[0].pixelFormat = format
        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }

    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame) {
        var uniforms = BackgroundUniforms(
            time: frame.time,
            level: frame.smoothed.level,
            aspect: frame.aspect,
            beat: frame.smoothed.beat,
            lowBand: frame.smoothed.low,
            midBand: frame.smoothed.mid,
            highBand: frame.smoothed.high,
            bpm: frame.features.bpm
        )
        var palette = PaletteUniforms(
            primary: SIMD4(frame.palette.primary, 1),
            secondary: SIMD4(frame.palette.secondary, 1),
            accent: SIMD4(frame.palette.accent, 1),
            background: SIMD4(frame.palette.background, 1)
        )

        encoder.label = "Background"
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBytes(&uniforms,
                               length: MemoryLayout<BackgroundUniforms>.stride,
                               index: 0)
        encoder.setFragmentBytes(&uniforms,
                                 length: MemoryLayout<BackgroundUniforms>.stride,
                                 index: 0)
        encoder.setFragmentBuffer(frame.magnitudesBuffer, offset: 0, index: 1)
        encoder.setFragmentBytes(&palette,
                                 length: MemoryLayout<PaletteUniforms>.stride,
                                 index: 2)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
    }
}

enum RendererError: Error {
    case missingLibrary
    case missingFunction(String)
}

import Foundation
import Metal
import simd

struct AuroraVertex {
    var position: SIMD3<Float>
    var uv: SIMD2<Float>
}

struct AuroraUniforms {
    var viewProjection: simd_float4x4
    var time: Float
    var level: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var beat: Float
    var loudness: Float
    var ribbonIndex: Float
}

@MainActor
final class AuroraVisualizer: VisualizerMode {
    static let id: VisualizerID = .aurora

    private let device: any MTLDevice
    private let background: BackgroundPass
    private let pipeline: any MTLRenderPipelineState
    private let vertexBuffer: any MTLBuffer
    private let indexBuffer: any MTLBuffer
    private let indexCount: Int

    private let cols = 96
    private let rows = 32
    private let ribbonCount = 4

    init(device: any MTLDevice, format: MTLPixelFormat) throws {
        self.device = device
        self.background = try BackgroundPass(device: device, format: format)

        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.missingLibrary
        }
        guard let vfn = library.makeFunction(name: "aurora_vertex"),
              let ffn = library.makeFunction(name: "aurora_fragment") else {
            throw RendererError.missingFunction("aurora_vertex / aurora_fragment")
        }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.label = "Aurora"
        descriptor.vertexFunction = vfn
        descriptor.fragmentFunction = ffn

        let color = descriptor.colorAttachments[0]!
        color.pixelFormat = format
        color.isBlendingEnabled = true
        color.rgbBlendOperation = .add
        color.alphaBlendOperation = .add
        color.sourceRGBBlendFactor = .sourceAlpha
        color.sourceAlphaBlendFactor = .one
        color.destinationRGBBlendFactor = .one
        color.destinationAlphaBlendFactor = .one

        self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)

        let (verts, idx) = Self.makeRibbonMesh(cols: cols, rows: rows)
        guard let vb = device.makeBuffer(
                bytes: verts,
                length: verts.count * MemoryLayout<AuroraVertex>.stride,
                options: .storageModeShared),
              let ib = device.makeBuffer(
                bytes: idx,
                length: idx.count * MemoryLayout<UInt32>.stride,
                options: .storageModeShared) else {
            throw RendererError.missingLibrary
        }
        vb.label = "Aurora.vertices"
        ib.label = "Aurora.indices"
        self.vertexBuffer = vb
        self.indexBuffer = ib
        self.indexCount = idx.count
    }

    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame) {
        background.encode(into: encoder, frame: frame)

        encoder.label = "Aurora"
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        var palette = PaletteUniforms(
            primary: SIMD4(frame.palette.primary, 1),
            secondary: SIMD4(frame.palette.secondary, 1),
            accent: SIMD4(frame.palette.accent, 1),
            background: SIMD4(frame.palette.background, 1)
        )
        encoder.setFragmentBytes(&palette,
                                 length: MemoryLayout<PaletteUniforms>.stride,
                                 index: 2)

        let projection = MatrixMath.perspective(
            fovYRadians: 0.78,
            aspect: max(0.01, frame.aspect),
            near: 0.05,
            far: 30
        )

        // Slow orbital dolly: a subtle Y-rotation + a breathing zoom along Z.
        let breath: Float = 1.0 + 0.10 * sinf(frame.time * 0.18)
        let view = MatrixMath.translation(SIMD3(0, 0.05, -2.55 * breath)) *
                   MatrixMath.rotationX(-0.22) *
                   MatrixMath.rotationY(sinf(frame.time * 0.05) * 0.32)
        let viewProjection = projection * view

        for i in 0..<ribbonCount {
            let phase = Float(i) - Float(ribbonCount - 1) / 2.0
            var uniforms = AuroraUniforms(
                viewProjection: viewProjection,
                time: frame.time + phase * 1.7,
                level: frame.smoothed.level,
                lowBand: frame.smoothed.low,
                midBand: frame.smoothed.mid,
                highBand: frame.smoothed.high,
                beat: frame.smoothed.beat,
                loudness: frame.smoothed.loudness,
                ribbonIndex: Float(i)
            )
            encoder.setVertexBytes(&uniforms,
                                   length: MemoryLayout<AuroraUniforms>.stride,
                                   index: 1)
            encoder.setFragmentBytes(&uniforms,
                                     length: MemoryLayout<AuroraUniforms>.stride,
                                     index: 1)
            encoder.drawIndexedPrimitives(
                type: .triangle,
                indexCount: indexCount,
                indexType: .uint32,
                indexBuffer: indexBuffer,
                indexBufferOffset: 0
            )
        }
    }

    private static func makeRibbonMesh(cols: Int, rows: Int) -> ([AuroraVertex], [UInt32]) {
        let width: Float = 5.6
        let depth: Float = 1.65
        var verts: [AuroraVertex] = []
        verts.reserveCapacity((cols + 1) * (rows + 1))
        for y in 0...rows {
            for x in 0...cols {
                let u = Float(x) / Float(cols)
                let v = Float(y) / Float(rows)
                let px = (u - 0.5) * width
                let pz = (v - 0.5) * depth
                verts.append(AuroraVertex(
                    position: SIMD3(px, 0, pz),
                    uv: SIMD2(u, v)
                ))
            }
        }

        var indices: [UInt32] = []
        indices.reserveCapacity(cols * rows * 6)
        let stride = UInt32(cols + 1)
        for y in 0..<UInt32(rows) {
            for x in 0..<UInt32(cols) {
                let a = y * stride + x
                let b = y * stride + x + 1
                let c = (y + 1) * stride + x
                let d = (y + 1) * stride + x + 1
                indices.append(contentsOf: [a, b, c, b, d, c])
            }
        }
        return (verts, indices)
    }
}

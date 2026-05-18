import Foundation
import Metal
import simd

struct LatticeUniforms {
    var viewProjection: simd_float4x4
    var time: Float
    var lowBand: Float
    var midBand: Float
    var highBand: Float
    var beat: Float
    var loudness: Float
    var spacing: Float
    var cellWidth: Float
    var cols: UInt32
    var rows: UInt32
    var audioGain: Float
}

@MainActor
final class LatticeVisualizer: VisualizerMode {
    static let id: VisualizerID = .lattice

    private let background: BackgroundPass
    private let pipeline: any MTLRenderPipelineState
    private let depthState: any MTLDepthStencilState
    private let vertexBuffer: any MTLBuffer
    private let indexBuffer: any MTLBuffer
    private let indexCount: Int

    private let cols: UInt32 = 22
    private let rows: UInt32 = 22

    init(device: any MTLDevice, format: MTLPixelFormat) throws {
        self.background = try BackgroundPass(device: device, format: format)

        guard let library = device.makeDefaultLibrary() else {
            throw RendererError.missingLibrary
        }
        guard let vfn = library.makeFunction(name: "lattice_vertex"),
              let ffn = library.makeFunction(name: "lattice_fragment") else {
            throw RendererError.missingFunction("lattice shaders")
        }

        let desc = MTLRenderPipelineDescriptor()
        desc.label = "Lattice"
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

        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .always
        depthDesc.isDepthWriteEnabled = false
        guard let depthState = device.makeDepthStencilState(descriptor: depthDesc) else {
            throw RendererError.missingLibrary
        }
        self.depthState = depthState

        let (verts, idx) = Self.makeUnitCube()
        guard let vb = device.makeBuffer(
                bytes: verts,
                length: verts.count * MemoryLayout<SIMD3<Float>>.stride,
                options: .storageModeShared),
              let ib = device.makeBuffer(
                bytes: idx,
                length: idx.count * MemoryLayout<UInt16>.stride,
                options: .storageModeShared) else {
            throw RendererError.missingLibrary
        }
        vb.label = "Lattice.unitCube"
        ib.label = "Lattice.cubeIndices"
        self.vertexBuffer = vb
        self.indexBuffer = ib
        self.indexCount = idx.count
    }

    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame) {
        background.encode(into: encoder, frame: frame)

        let projection = MatrixMath.perspective(
            fovYRadians: 0.78,
            aspect: max(0.01, frame.aspect),
            near: 0.05,
            far: 60
        )
        let breath = 1.0 + 0.04 * sinf(frame.time * 0.4)
        let view = MatrixMath.translation(SIMD3(0, -1.1, -10.5 * Float(breath))) *
                   MatrixMath.rotationX(0.62) *
                   MatrixMath.rotationY(frame.time * 0.10)

        var u = LatticeUniforms(
            viewProjection: projection * view,
            time: frame.time,
            lowBand: frame.smoothed.low,
            midBand: frame.smoothed.mid,
            highBand: frame.smoothed.high,
            beat: frame.smoothed.beat,
            loudness: frame.smoothed.loudness,
            spacing: 0.55,
            cellWidth: 0.18,
            cols: cols,
            rows: rows,
            audioGain: 6.0
        )
        var palette = PaletteUniforms(
            primary: SIMD4(frame.palette.primary, 1),
            secondary: SIMD4(frame.palette.secondary, 1),
            accent: SIMD4(frame.palette.accent, 1),
            background: SIMD4(frame.palette.background, 1)
        )

        encoder.label = "Lattice"
        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setVertexBytes(&u, length: MemoryLayout<LatticeUniforms>.stride, index: 1)
        encoder.setVertexBuffer(frame.magnitudesBuffer, offset: 0, index: 2)
        encoder.setFragmentBytes(&u, length: MemoryLayout<LatticeUniforms>.stride, index: 1)
        encoder.setFragmentBytes(&palette,
                                 length: MemoryLayout<PaletteUniforms>.stride,
                                 index: 2)

        encoder.drawIndexedPrimitives(
            type: .triangle,
            indexCount: indexCount,
            indexType: .uint16,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0,
            instanceCount: Int(cols * rows)
        )
    }

    private static func makeUnitCube() -> ([SIMD3<Float>], [UInt16]) {
        let vertices: [SIMD3<Float>] = [
            SIMD3(-0.5, 0.0, -0.5),
            SIMD3( 0.5, 0.0, -0.5),
            SIMD3( 0.5, 1.0, -0.5),
            SIMD3(-0.5, 1.0, -0.5),
            SIMD3(-0.5, 0.0,  0.5),
            SIMD3( 0.5, 0.0,  0.5),
            SIMD3( 0.5, 1.0,  0.5),
            SIMD3(-0.5, 1.0,  0.5)
        ]
        let indices: [UInt16] = [
            0, 1, 2,  0, 2, 3,
            4, 6, 5,  4, 7, 6,
            0, 3, 7,  0, 7, 4,
            1, 5, 6,  1, 6, 2,
            3, 2, 6,  3, 6, 7,
            0, 4, 5,  0, 5, 1
        ]
        return (vertices, indices)
    }
}

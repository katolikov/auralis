import Foundation
import simd

enum MatrixMath {
    static func perspective(fovYRadians: Float,
                            aspect: Float,
                            near: Float,
                            far: Float) -> simd_float4x4 {
        let f = 1 / tanf(fovYRadians / 2)
        let nf = 1 / (near - far)
        return simd_float4x4(columns: (
            SIMD4(f / aspect, 0, 0, 0),
            SIMD4(0, f, 0, 0),
            SIMD4(0, 0, (far + near) * nf, -1),
            SIMD4(0, 0, 2 * far * near * nf, 0)
        ))
    }

    static func translation(_ t: SIMD3<Float>) -> simd_float4x4 {
        var m = matrix_identity_float4x4
        m.columns.3 = SIMD4(t.x, t.y, t.z, 1)
        return m
    }

    static func scale(_ s: SIMD3<Float>) -> simd_float4x4 {
        simd_float4x4(diagonal: SIMD4(s.x, s.y, s.z, 1))
    }

    static func rotationX(_ angle: Float) -> simd_float4x4 {
        let c = cosf(angle), s = sinf(angle)
        return simd_float4x4(columns: (
            SIMD4(1, 0, 0, 0),
            SIMD4(0, c, s, 0),
            SIMD4(0, -s, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func rotationY(_ angle: Float) -> simd_float4x4 {
        let c = cosf(angle), s = sinf(angle)
        return simd_float4x4(columns: (
            SIMD4(c, 0, -s, 0),
            SIMD4(0, 1, 0, 0),
            SIMD4(s, 0, c, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }

    static func rotationZ(_ angle: Float) -> simd_float4x4 {
        let c = cosf(angle), s = sinf(angle)
        return simd_float4x4(columns: (
            SIMD4(c, s, 0, 0),
            SIMD4(-s, c, 0, 0),
            SIMD4(0, 0, 1, 0),
            SIMD4(0, 0, 0, 1)
        ))
    }
}

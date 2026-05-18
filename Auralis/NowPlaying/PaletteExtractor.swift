import AppKit
import CoreGraphics
import Foundation
import simd

/// k-means++ palette extractor over a downsampled CGImage.
/// Returns up to `k` colors ranked by visual presence (chroma × value).
struct PaletteExtractor: Sendable {
    let downsampleSize: Int
    let k: Int
    let iterations: Int

    init(downsampleSize: Int = 32, k: Int = 5, iterations: Int = 12) {
        self.downsampleSize = downsampleSize
        self.k = k
        self.iterations = iterations
    }

    func extract(from cgImage: CGImage) -> [SIMD3<Float>] {
        guard let pixels = downsample(cgImage), !pixels.isEmpty else { return [] }
        let centers = kmeans(pixels: pixels)
        return rank(centers)
    }

    private func downsample(_ cg: CGImage) -> [SIMD3<Float>]? {
        let w = downsampleSize
        let h = downsampleSize
        let bytesPerRow = w * 4
        var buf = [UInt8](repeating: 0, count: bytesPerRow * h)
        guard let ctx = buf.withUnsafeMutableBufferPointer({ ptr in
            CGContext(
                data: ptr.baseAddress,
                width: w, height: h,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)
                    ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                    | CGBitmapInfo.byteOrder32Big.rawValue
            )
        }) else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))

        var pixels: [SIMD3<Float>] = []
        pixels.reserveCapacity(w * h)
        for i in 0..<(w * h) {
            let r = Float(buf[i * 4 + 0]) / 255
            let g = Float(buf[i * 4 + 1]) / 255
            let b = Float(buf[i * 4 + 2]) / 255
            pixels.append(SIMD3<Float>(r, g, b))
        }
        return pixels
    }

    private func kmeans(pixels: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard pixels.count >= k else { return Array(pixels.prefix(k)) }

        var centers: [SIMD3<Float>] = []
        centers.append(pixels[pixels.count / 2])

        // k-means++ seeding
        while centers.count < k {
            var bestDist: Float = -1
            var bestIndex = 0
            for (i, p) in pixels.enumerated() {
                var minD: Float = .greatestFiniteMagnitude
                for c in centers {
                    let d = simd_distance_squared(p, c)
                    if d < minD { minD = d }
                }
                if minD > bestDist {
                    bestDist = minD
                    bestIndex = i
                }
            }
            centers.append(pixels[bestIndex])
        }

        // Lloyd's iterations
        for _ in 0..<iterations {
            var sums = Array(repeating: SIMD3<Float>.zero, count: k)
            var counts = Array(repeating: 0, count: k)
            for p in pixels {
                var bestI = 0
                var bestD = simd_distance_squared(p, centers[0])
                for i in 1..<k {
                    let d = simd_distance_squared(p, centers[i])
                    if d < bestD { bestD = d; bestI = i }
                }
                sums[bestI] += p
                counts[bestI] += 1
            }
            var moved: Float = 0
            for i in 0..<k where counts[i] > 0 {
                let updated = sums[i] / Float(counts[i])
                moved += simd_distance(updated, centers[i])
                centers[i] = updated
            }
            if moved < 1e-3 { break }
        }
        return centers
    }

    private func rank(_ centers: [SIMD3<Float>]) -> [SIMD3<Float>] {
        centers.sorted { score($0) > score($1) }
    }

    private func score(_ c: SIMD3<Float>) -> Float {
        let maxC = max(c.x, max(c.y, c.z))
        let minC = min(c.x, min(c.y, c.z))
        let chroma = maxC - minC
        let value = maxC
        // Penalize near-black and near-white extremes a touch.
        let bias = 1.0 - 2.0 * abs(value - 0.55)
        return chroma * 0.65 + value * 0.20 + max(0, bias) * 0.15
    }
}

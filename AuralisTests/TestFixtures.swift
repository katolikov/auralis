import CoreGraphics
import Foundation
import Metal
import simd
@testable import Auralis

enum TestFixtures {
    static func sampleMagnitudes() -> [Float] {
        var mags = [Float](repeating: 0, count: AudioFeatures.binCount)
        for i in 0..<mags.count {
            let t = Float(i) / Float(mags.count - 1)
            mags[i] = 0.30 * powf(1.0 - t, 1.7) +
                      expf(-powf((t - 0.30) * 8.5, 2.0)) * 0.20 +
                      expf(-powf((t - 0.65) * 9.5, 2.0)) * 0.10
        }
        return mags
    }

    static func sampleFeatures(magnitudes: [Float]) -> AudioFeatures {
        AudioFeatures(
            level: 0.4,
            loudness: 0.35,
            lowBand: 0.30,
            midBand: 0.25,
            highBand: 0.18,
            magnitudes: magnitudes,
            beat: 0.5,
            didBeat: true,
            bpm: 120,
            timestamp: 0
        )
    }

    static func samplePalette() -> Theme.Snapshot {
        Theme.Snapshot(
            primary:    SIMD3<Float>(0.42, 0.78, 0.96),
            secondary:  SIMD3<Float>(0.55, 0.40, 0.92),
            accent:     SIMD3<Float>(0.96, 0.55, 0.82),
            background: SIMD3<Float>(0.020, 0.025, 0.060)
        )
    }

    @MainActor
    static func sampleFrame(renderer: OffscreenRenderer,
                            time: Float = 2.4) -> VisualizerFrame {
        let mags = sampleMagnitudes()
        renderer.uploadMagnitudes(mags)
        let features = sampleFeatures(magnitudes: mags)
        return VisualizerFrame(
            time: time,
            aspect: 16.0 / 9.0,
            features: features,
            smoothed: SmoothedFeatures(
                level: features.level,
                loudness: features.loudness,
                low: features.lowBand,
                mid: features.midBand,
                high: features.highBand,
                beat: features.beat
            ),
            palette: samplePalette(),
            magnitudesBuffer: renderer.magnitudesBuffer
        )
    }

    static func pixelVariance(_ image: CGImage) -> Double {
        guard let provider = image.dataProvider,
              let data = provider.data,
              CFDataGetLength(data) > 0 else { return 0 }
        let ptr = CFDataGetBytePtr(data)!
        let count = CFDataGetLength(data)
        guard count >= 16 else { return 0 }

        var sum: Double = 0
        var sumSq: Double = 0
        var samples = 0
        // Sample every 8th pixel (RGBA stride 4) to keep variance cheap.
        for i in stride(from: 0, to: count, by: 32) {
            let r = Double(ptr[i]) / 255.0
            let g = Double(ptr[i + 1]) / 255.0
            let b = Double(ptr[i + 2]) / 255.0
            let lum = 0.299 * r + 0.587 * g + 0.114 * b
            sum += lum
            sumSq += lum * lum
            samples += 1
        }
        guard samples > 0 else { return 0 }
        let mean = sum / Double(samples)
        return (sumSq / Double(samples)) - mean * mean
    }
}

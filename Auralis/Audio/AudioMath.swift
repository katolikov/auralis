import Accelerate
import AVFoundation
import CoreMedia

enum AudioMath {
    /// Calls `body` with a non-interleaved `AudioBufferList` of Float32
    /// samples backing the sample buffer. Returns `nil` on failure.
    static func withSamples<R>(
        of buffer: CMSampleBuffer,
        _ body: (UnsafeMutableAudioBufferListPointer, Int) -> R
    ) -> R? {
        var sizeNeeded = 0
        let first = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard first == noErr || first == kCMSampleBufferError_ArrayTooSmall,
              sizeNeeded > 0 else { return nil }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: abl,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else { return nil }

        let frames = Int(CMSampleBufferGetNumSamples(buffer))
        return body(UnsafeMutableAudioBufferListPointer(abl), frames)
    }

    /// Mean square of a Float32 buffer, in place.
    @inline(__always)
    static func meanSquare(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        var ms: Float = 0
        vDSP_measqv(samples, 1, &ms, vDSP_Length(count))
        return ms
    }

    @inline(__always)
    static func rms(_ samples: UnsafePointer<Float>, count: Int) -> Float {
        sqrtf(meanSquare(samples, count: count))
    }
}

/// Maps a half-spectrum magnitude array into log-spaced bins from
/// `minHz` to `maxHz`. Edges are precomputed at init.
struct LogBinner: Sendable {
    let binCount: Int
    let fftSize: Int
    let sampleRate: Float
    private let edges: [Int]

    init(binCount: Int = AudioFeatures.binCount,
         fftSize: Int,
         sampleRate: Float,
         minHz: Float = 20,
         maxHz: Float = 20_000) {
        self.binCount = binCount
        self.fftSize = fftSize
        self.sampleRate = sampleRate

        let halfN = fftSize / 2
        let binWidth = sampleRate / Float(fftSize)
        let logMin = log10f(max(minHz, binWidth))
        let logMax = log10f(min(maxHz, sampleRate * 0.5))

        var raw = [Int](repeating: 0, count: binCount + 1)
        for i in 0...binCount {
            let t = Float(i) / Float(binCount)
            let hz = powf(10, logMin + t * (logMax - logMin))
            raw[i] = min(max(0, Int(round(hz / binWidth))), halfN - 1)
        }
        // Guarantee each bin spans at least one FFT bin.
        for i in 1...binCount where raw[i] <= raw[i - 1] {
            raw[i] = raw[i - 1] + 1
        }
        self.edges = raw
    }

    func bin(magnitudes: UnsafePointer<Float>, count: Int) -> [Float] {
        var out = [Float](repeating: 0, count: binCount)
        for i in 0..<binCount {
            let lo = edges[i]
            let hi = min(edges[i + 1], count)
            guard hi > lo else { continue }
            var sum: Float = 0
            vDSP_sve(magnitudes + lo, 1, &sum, vDSP_Length(hi - lo))
            out[i] = sum / Float(hi - lo)
        }
        return out
    }
}

/// Sum-and-average band aggregator. Uses raw FFT bins for accuracy
/// rather than the log-binned re-projection.
struct BandComputer: Sendable {
    let sampleRate: Float
    let fftSize: Int

    private let lowRange: Range<Int>
    private let midRange: Range<Int>
    private let highRange: Range<Int>

    init(sampleRate: Float, fftSize: Int) {
        self.sampleRate = sampleRate
        self.fftSize = fftSize
        let binWidth = sampleRate / Float(fftSize)
        let halfN = fftSize / 2
        func clampRange(_ loHz: Float, _ hiHz: Float) -> Range<Int> {
            let lo = max(1, min(halfN - 1, Int(loHz / binWidth)))
            let hi = max(lo + 1, min(halfN, Int(hiHz / binWidth)))
            return lo..<hi
        }
        self.lowRange = clampRange(20, 250)
        self.midRange = clampRange(250, 4_000)
        self.highRange = clampRange(4_000, 16_000)
    }

    func compute(magnitudes: UnsafePointer<Float>, count: Int) -> (low: Float, mid: Float, high: Float) {
        func mean(_ range: Range<Int>) -> Float {
            let clamped = range.lowerBound..<min(range.upperBound, count)
            guard clamped.count > 0 else { return 0 }
            var sum: Float = 0
            vDSP_sve(magnitudes + clamped.lowerBound, 1, &sum, vDSP_Length(clamped.count))
            return sum / Float(clamped.count)
        }
        return (mean(lowRange), mean(midRange), mean(highRange))
    }

    /// Coarse A-weighting approximation: weight bands by their perceptual
    /// curve at ~1 kHz centroid. Good enough for visualizer dynamics.
    func aWeightedLoudness(low: Float, mid: Float, high: Float) -> Float {
        // A-weight roughly: low -16 dB, mid 0 dB, high -3 dB.
        let w = 0.158 * low + 1.0 * mid + 0.708 * high
        return w / (1.0 + 0.158 + 0.708)
    }
}

import Foundation

/// Spectral-flux onset detector with adaptive median+MAD thresholding.
/// Emits a per-frame envelope (1 on onset, exponentially decays toward 0)
/// plus a `didFire` flag, and maintains a rolling BPM estimate from recent
/// inter-onset intervals.
final class OnsetDetector {
    private let historySize: Int
    private let minInterval: TimeInterval
    private let envelopeTau: Float
    private let threshold: Float

    private var lastMagnitudes: [Float] = []
    private var fluxHistory: [Float] = []
    private var lastUpdate: TimeInterval = 0
    private var lastBeatTime: TimeInterval = 0
    private var envelope: Float = 0
    private var beatTimes: [TimeInterval] = []
    private(set) var bpm: Float = 0

    init(historySize: Int = 43,
         minInterval: TimeInterval = 0.18,
         envelopeTau: Float = 0.18,
         threshold: Float = 1.6) {
        self.historySize = historySize
        self.minInterval = minInterval
        self.envelopeTau = envelopeTau
        self.threshold = threshold
    }

    /// Returns the current beat envelope and whether the detector fired
    /// on this frame. `magnitudes` is expected to be the log-binned
    /// spectrum (consistent dimensionality across calls).
    func process(magnitudes: [Float], at time: TimeInterval) -> (envelope: Float, fired: Bool) {
        if lastUpdate > 0 {
            let dt = Float(time - lastUpdate)
            if dt > 0 {
                envelope *= expf(-dt / envelopeTau)
            }
        }
        lastUpdate = time

        guard lastMagnitudes.count == magnitudes.count else {
            lastMagnitudes = magnitudes
            return (envelope, false)
        }

        var flux: Float = 0
        for i in 0..<magnitudes.count {
            let d = magnitudes[i] - lastMagnitudes[i]
            if d > 0 { flux += d }
        }
        lastMagnitudes = magnitudes

        fluxHistory.append(flux)
        if fluxHistory.count > historySize {
            fluxHistory.removeFirst()
        }
        guard fluxHistory.count >= 8 else {
            return (envelope, false)
        }

        let sorted = fluxHistory.sorted()
        let median = sorted[sorted.count / 2]
        var deviations = sorted.map { abs($0 - median) }
        deviations.sort()
        let mad = deviations[deviations.count / 2]
        let cutoff = median + threshold * mad + 1e-6

        let elapsed = time - lastBeatTime
        guard flux > cutoff, elapsed > minInterval else {
            return (envelope, false)
        }

        envelope = 1.0
        lastBeatTime = time
        beatTimes.append(time)
        if beatTimes.count > 16 {
            beatTimes.removeFirst()
        }
        updateBPM()
        return (envelope, true)
    }

    private func updateBPM() {
        guard beatTimes.count >= 4 else { return }
        var intervals: [Float] = []
        intervals.reserveCapacity(beatTimes.count - 1)
        for i in 1..<beatTimes.count {
            intervals.append(Float(beatTimes[i] - beatTimes[i - 1]))
        }
        let mean = intervals.reduce(0, +) / Float(intervals.count)
        guard mean > 0 else { return }
        bpm = min(240, max(40, 60.0 / mean))
    }
}

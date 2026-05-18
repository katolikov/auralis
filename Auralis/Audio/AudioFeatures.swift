import Foundation

/// Snapshot of audio features for a single analysis window (2048 samples
/// at 48 kHz, hop 1024 → emitted ~46.9 Hz). All magnitudes are linear,
/// normalized so that a full-scale sine emits roughly 1.0.
struct AudioFeatures: Sendable {
    static let binCount = 64

    /// Broadband RMS over the analysis window.
    var level: Float
    /// A-weighted loudness approximation.
    var loudness: Float

    /// 20–250 Hz mean magnitude.
    var lowBand: Float
    /// 250 Hz–4 kHz mean magnitude.
    var midBand: Float
    /// 4 kHz–16 kHz mean magnitude.
    var highBand: Float

    /// Log-spaced magnitude bins (`binCount` entries, 20 Hz → 20 kHz).
    var magnitudes: [Float]

    /// 0…1 envelope, snaps to 1 on onset and decays toward 0.
    var beat: Float
    /// True only on the analysis frame the onset detector fired.
    var didBeat: Bool
    /// Best-effort tempo estimate derived from recent beat intervals.
    var bpm: Float

    var timestamp: TimeInterval

    static let silent = AudioFeatures(
        level: 0,
        loudness: 0,
        lowBand: 0,
        midBand: 0,
        highBand: 0,
        magnitudes: Array(repeating: 0, count: binCount),
        beat: 0,
        didBeat: false,
        bpm: 0,
        timestamp: 0
    )
}

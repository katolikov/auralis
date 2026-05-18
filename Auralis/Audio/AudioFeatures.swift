import Foundation

/// Snapshot of audio features for a single analysis window.
///
/// Milestone 1 publishes only the broadband RMS level; later milestones
/// expand this to log-binned magnitudes, band energies, onset triggers,
/// and palette-driven color uniforms.
struct AudioFeatures: Sendable, Equatable {
    var level: Float
    var timestamp: TimeInterval

    static let silent = AudioFeatures(level: 0, timestamp: 0)
}

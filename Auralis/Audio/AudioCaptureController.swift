import AppKit
import Combine
import CoreGraphics
import Foundation

/// MainActor-facing facade around `SystemAudioCapture`.
///
/// Owns permission flow, runs the consumer task, and republishes audio
/// features to SwiftUI. Smoothed level is what the UI/shader should bind
/// to; raw level is kept for debug/HUD readouts.
@MainActor
final class AudioCaptureController: ObservableObject {
    @Published private(set) var rawLevel: Float = 0
    @Published private(set) var smoothedLevel: Float = 0
    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?

    private let capture = SystemAudioCapture()
    private var consumeTask: Task<Void, Never>?
    private let smoothingAttack: Float = 0.45
    private let smoothingRelease: Float = 0.08

    func start() async {
        guard !isRunning else { return }

        guard CGPreflightScreenCaptureAccess() else {
            _ = CGRequestScreenCaptureAccess()
            statusMessage = "Grant Screen Recording in System Settings, then relaunch Auralis."
            return
        }

        consumeTask?.cancel()
        consumeTask = Task { [weak self, capture] in
            for await features in capture.featureStream {
                guard let self else { return }
                await self.ingest(features)
            }
        }

        do {
            try await capture.start()
            isRunning = true
            statusMessage = nil
        } catch {
            isRunning = false
            statusMessage = (error as? LocalizedError)?.errorDescription
                ?? "Capture error: \(error.localizedDescription)"
            consumeTask?.cancel()
            consumeTask = nil
        }
    }

    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        await capture.stop()
        isRunning = false
    }

    private func ingest(_ features: AudioFeatures) {
        rawLevel = features.level
        let target = features.level
        let coef = target > smoothedLevel ? smoothingAttack : smoothingRelease
        smoothedLevel += coef * (target - smoothedLevel)
    }
}

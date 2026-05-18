import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AudioCaptureController: ObservableObject {
    @Published private(set) var features: AudioFeatures = .silent

    @Published private(set) var smoothedLevel: Float = 0
    @Published private(set) var smoothedLoudness: Float = 0
    @Published private(set) var smoothedLow: Float = 0
    @Published private(set) var smoothedMid: Float = 0
    @Published private(set) var smoothedHigh: Float = 0
    @Published private(set) var smoothedBeat: Float = 0
    @Published private(set) var bpm: Float = 0

    @Published private(set) var isRunning = false
    @Published private(set) var statusMessage: String?

    @Published var showDebugHUD = false

    private let capture = SystemAudioCapture()
    private var consumeTask: Task<Void, Never>?

    private let attack: Float = 0.45
    private let release: Float = 0.10

    func start() async {
        guard !isRunning else { return }

        // Poll for Screen Recording permission. The first miss triggers
        // CGRequestScreenCaptureAccess (which registers the app in TCC
        // and pops System Settings), then we wait until the grant lands
        // and continue automatically — no relaunch required.
        var requested = false
        while !CGPreflightScreenCaptureAccess() {
            if Task.isCancelled { return }
            if !requested {
                _ = CGRequestScreenCaptureAccess()
                requested = true
            }
            statusMessage =
                "Grant Screen Recording in System Settings — Auralis starts the moment it's enabled."
            try? await Task.sleep(for: .seconds(2))
        }

        consumeTask?.cancel()
        consumeTask = Task { @MainActor [weak self, capture] in
            for await features in capture.featureStream {
                self?.ingest(features)
            }
        }

        do {
            try await capture.start()
            isRunning = true
            statusMessage = nil
        } catch {
            isRunning = false
            statusMessage = (error as? any LocalizedError)?.errorDescription
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

    func toggleDebugHUD() {
        showDebugHUD.toggle()
    }

    private func ingest(_ f: AudioFeatures) {
        features = f
        smoothedLevel = smooth(target: f.level, current: smoothedLevel)
        smoothedLoudness = smooth(target: f.loudness, current: smoothedLoudness)
        smoothedLow = smooth(target: f.lowBand, current: smoothedLow)
        smoothedMid = smooth(target: f.midBand, current: smoothedMid)
        smoothedHigh = smooth(target: f.highBand, current: smoothedHigh)
        smoothedBeat = smooth(target: f.beat,
                              current: smoothedBeat,
                              attackOverride: 0.9)
        bpm = f.bpm
    }

    private func smooth(target: Float,
                        current: Float,
                        attackOverride: Float? = nil) -> Float {
        let coef = target > current
            ? (attackOverride ?? attack)
            : release
        return current + coef * (target - current)
    }
}

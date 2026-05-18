import AppKit
import Combine
import CoreGraphics
import Foundation

@MainActor
final class AudioCaptureController: ObservableObject {
    enum ActionRequired: Sendable {
        case openSettings
        case relaunch
    }

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
    @Published private(set) var actionRequired: ActionRequired?

    @Published var showDebugHUD = false

    private let capture = SystemAudioCapture()
    private var consumeTask: Task<Void, Never>?

    private let attack: Float = 0.45
    private let release: Float = 0.10

    func start() async {
        guard !isRunning else { return }

        var permissionPrompted = false
        var consecutiveFailures = 0

        while !isRunning {
            if Task.isCancelled { return }

            do {
                try await capture.start()
                consumeTask?.cancel()
                consumeTask = Task { @MainActor [weak self, capture] in
                    for await features in capture.featureStream {
                        self?.ingest(features)
                    }
                }
                isRunning = true
                statusMessage = nil
                actionRequired = nil
                return
            } catch {
                consecutiveFailures += 1
                let granted = CGPreflightScreenCaptureAccess()

                if !granted {
                    if !permissionPrompted {
                        _ = CGRequestScreenCaptureAccess()
                        permissionPrompted = true
                    }
                    actionRequired = .openSettings
                    statusMessage = "Tap here · enable Auralis under Screen Recording in System Settings."
                } else if consecutiveFailures >= 2 {
                    // Preflight says granted but the SCK call still fails.
                    // ScreenCaptureKit caches its TCC decision per-process —
                    // a fresh process is the reliable way to pick up the
                    // new grant. Offer a one-tap relaunch.
                    actionRequired = .relaunch
                    statusMessage = "Permission set. Tap to relaunch Auralis and start capture."
                } else if let localized = (error as? any LocalizedError)?.errorDescription {
                    actionRequired = nil
                    statusMessage = localized
                } else {
                    actionRequired = nil
                    statusMessage = "Starting capture…"
                }

                try? await Task.sleep(for: .seconds(2))
            }
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

    func performAction() {
        switch actionRequired {
        case .openSettings:
            if let url = URL(string:
                "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        case .relaunch:
            relaunchSelf()
        case .none:
            break
        }
    }

    private func relaunchSelf() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: bundleURL,
                                            configuration: configuration) { _, _ in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(350))
                NSApp.terminate(nil)
            }
        }
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

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
        var preflightDeniedCycles = 0
        var failuresAfterGrant = 0

        while !isRunning {
            if Task.isCancelled { return }

            // Gate the SCK call on preflight so we don't re-trigger
            // macOS's modal permission dialog on each retry.
            if !CGPreflightScreenCaptureAccess() {
                if !permissionPrompted {
                    _ = CGRequestScreenCaptureAccess()
                    permissionPrompted = true
                }
                preflightDeniedCycles += 1

                // After ~6 s of "still denied" post-prompt, assume the
                // user has either enabled the toggle (and TCC is just
                // caching the old verdict for our process) or hasn't
                // done so yet. Either way, a relaunch resolves it: a
                // fresh process re-reads TCC; if grant isn't there, it
                // re-enters this loop and shows the openSettings hint.
                if preflightDeniedCycles >= 3 {
                    actionRequired = .relaunch
                    statusMessage = "If Auralis is enabled in Screen Recording, tap to relaunch — macOS caches the verdict per process."
                } else {
                    actionRequired = .openSettings
                    statusMessage = "Tap here · enable Auralis under Screen Recording in System Settings."
                }
                try? await Task.sleep(for: .seconds(2))
                continue
            }

            // Preflight says granted. Try the actual SCK call. If even
            // that fails, fall back to the relaunch escape hatch.
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
                failuresAfterGrant += 1
                if failuresAfterGrant >= 2 {
                    actionRequired = .relaunch
                    statusMessage = "Permission set. Tap to relaunch Auralis and start capture."
                    try? await Task.sleep(for: .seconds(5))
                } else if let localized = (error as? any LocalizedError)?.errorDescription {
                    actionRequired = nil
                    statusMessage = localized
                    try? await Task.sleep(for: .seconds(2))
                } else {
                    actionRequired = nil
                    statusMessage = "Starting capture…"
                    try? await Task.sleep(for: .seconds(2))
                }
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

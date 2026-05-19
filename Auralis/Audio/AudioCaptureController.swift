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
    private var escalationTask: Task<Void, Never>?

    private let attack: Float = 0.45
    private let release: Float = 0.10

    /// Single-shot start. Either succeeds and silences the chip, or
    /// fails and surfaces a tappable chip pointing to the right next
    /// step. No SCShareableContent retries — repeated calls would
    /// re-trigger macOS's TCC dialog when the system is undecided.
    func start() async {
        guard !isRunning else { return }

        do {
            try await capture.start()
            attachConsumer()
            isRunning = true
            statusMessage = nil
            actionRequired = nil
            escalationTask?.cancel()
        } catch {
            offerRemediation(initial: true)
        }
    }

    /// User-driven retry — only attempted when explicitly invoked
    /// (e.g. after they enable the toggle and we want to try again
    /// without a process restart).
    func retry() async {
        escalationTask?.cancel()
        statusMessage = "Starting capture…"
        actionRequired = nil
        await start()
    }

    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        escalationTask?.cancel()
        escalationTask = nil
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

    private func attachConsumer() {
        consumeTask?.cancel()
        consumeTask = Task { @MainActor [weak self, capture] in
            for await features in capture.featureStream {
                self?.ingest(features)
            }
        }
    }

    private func offerRemediation(initial: Bool) {
        let granted = CGPreflightScreenCaptureAccess()

        if initial && !granted {
            // Idempotent on subsequent calls — registers Auralis in the
            // TCC database if it isn't yet, otherwise no-op.
            _ = CGRequestScreenCaptureAccess()
        }

        if granted {
            actionRequired = .relaunch
            statusMessage = "Permission set. Tap to relaunch Auralis and start capture."
        } else {
            actionRequired = .openSettings
            statusMessage = "Tap here · enable Auralis under Screen Recording in System Settings."
        }

        // After ~6 seconds, escalate the openSettings chip into a
        // relaunch chip. macOS caches the TCC verdict per process —
        // once this process has been told "denied", flipping the
        // toggle in Settings does not update preflight for us. The
        // relaunch chip is the reliable way out of that state.
        escalationTask?.cancel()
        if actionRequired == .openSettings {
            escalationTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard !Task.isCancelled, let self else { return }
                guard self.actionRequired == .openSettings else { return }
                self.actionRequired = .relaunch
                self.statusMessage =
                    "If Auralis is enabled in Screen Recording, tap to relaunch — macOS caches the verdict per process."
            }
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

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
    private var monitorTask: Task<Void, Never>?

    private let attack: Float = 0.45
    private let release: Float = 0.10

    func start() async {
        guard !isRunning else { return }

        do {
            try await capture.start()
            attachConsumer()
            isRunning = true
            statusMessage = nil
            actionRequired = nil
            monitorTask?.cancel()
            monitorTask = nil
        } catch {
            offerRemediation()
        }
    }

    func stop() async {
        consumeTask?.cancel()
        consumeTask = nil
        monitorTask?.cancel()
        monitorTask = nil
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

    private func offerRemediation() {
        let granted = CGPreflightScreenCaptureAccess()

        // Idempotent — registers Auralis in TCC on first call ever
        // for this binary, no-op afterwards.
        if !granted {
            _ = CGRequestScreenCaptureAccess()
        }

        applyChip(granted: granted, sckRetried: false)
        startMonitor(initialGranted: granted)
    }

    /// Polls `CGPreflightScreenCaptureAccess` every 2 s. Preflight is
    /// dialog-free, so polling it is safe regardless of TCC state.
    /// When the verdict flips to granted, attempt the SCK call exactly
    /// once: if it works, capture starts and we're done; if it doesn't,
    /// surface the relaunch chip so the user can clear the process cache.
    private func startMonitor(initialGranted: Bool) {
        monitorTask?.cancel()
        monitorTask = Task { @MainActor [weak self] in
            var lastGranted = initialGranted
            var didRetryAfterFlip = false

            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                guard let self else { return }
                if self.isRunning {
                    self.monitorTask = nil
                    return
                }

                let granted = CGPreflightScreenCaptureAccess()
                if granted != lastGranted {
                    lastGranted = granted
                    didRetryAfterFlip = false
                    self.applyChip(granted: granted, sckRetried: false)
                }

                // Only retry SCK once per false→true preflight transition.
                // Never retry while denied (would re-trigger TCC dialog
                // when the system is in the "undecided" state).
                if granted && !didRetryAfterFlip {
                    didRetryAfterFlip = true
                    do {
                        try await self.capture.start()
                        self.attachConsumer()
                        self.isRunning = true
                        self.statusMessage = nil
                        self.actionRequired = nil
                        self.monitorTask = nil
                        return
                    } catch {
                        // Preflight reports granted, but SCK's per-process
                        // cache still says denied. Only way out: relaunch.
                        self.applyChip(granted: true, sckRetried: true)
                    }
                }
            }
        }
    }

    private func applyChip(granted: Bool, sckRetried: Bool) {
        if granted && sckRetried {
            actionRequired = .relaunch
            statusMessage = "Permission granted — but this process is stuck on a stale verdict. Tap to relaunch."
        } else if granted {
            actionRequired = .relaunch
            statusMessage = "Permission detected — tap to relaunch and start capture."
        } else {
            actionRequired = .openSettings
            statusMessage = "Tap here · enable Auralis under Screen Recording in System Settings."
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

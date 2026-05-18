import AVFoundation
import CoreMedia
import Foundation
import OSLog
import ScreenCaptureKit

enum CaptureError: LocalizedError {
    case musicNotRunning
    case noDisplay

    var errorDescription: String? {
        switch self {
        case .musicNotRunning:
            return "Apple Music isn't running. Launch Music and start playback."
        case .noDisplay:
            return "No display available for capture."
        }
    }
}

/// System-audio capture pipeline filtered to the Music app's bundle id.
///
/// SCStream requires a display to be selected even for audio-only capture;
/// we pick the main display at the minimum resolution and frame rate, then
/// rely on the `including:` content filter to restrict capture to
/// `com.apple.Music`. Audio samples are decoded on the SCK delivery queue
/// (off-actor) and yielded into an `AsyncStream` of `AudioFeatures`.
actor SystemAudioCapture {
    private static let log = Logger(subsystem: "app.auralis", category: "SystemAudioCapture")
    static let musicBundleID = "com.apple.Music"

    nonisolated let featureStream: AsyncStream<AudioFeatures>
    private nonisolated let continuation: AsyncStream<AudioFeatures>.Continuation

    private var stream: SCStream?
    private var output: AudioStreamOutput?

    init() {
        var cont: AsyncStream<AudioFeatures>.Continuation!
        self.featureStream = AsyncStream(bufferingPolicy: .bufferingNewest(2)) { c in
            cont = c
        }
        self.continuation = cont
    }

    deinit {
        continuation.finish()
    }

    func start() async throws {
        let content = try await SCShareableContent.excludingDesktopWindows(
            false,
            onScreenWindowsOnly: true
        )

        guard let musicApp = content.applications.first(where: {
            $0.bundleIdentifier == Self.musicBundleID
        }) else {
            throw CaptureError.musicNotRunning
        }

        guard let display = content.displays.first else {
            throw CaptureError.noDisplay
        }

        let filter = SCContentFilter(
            display: display,
            including: [musicApp],
            exceptingWindows: []
        )

        let config = SCStreamConfiguration()
        config.capturesAudio = true
        config.excludesCurrentProcessAudio = true
        config.sampleRate = 48_000
        config.channelCount = 2
        // Audio-only capture: keep video work near zero.
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let cont = self.continuation
        let output = AudioStreamOutput { buffer in
            let level = AudioMath.rms(buffer: buffer)
            cont.yield(AudioFeatures(level: level, timestamp: CACurrentMediaTime()))
        }

        let queue = DispatchQueue(label: "app.auralis.audio.delivery", qos: .userInteractive)
        try stream.addStreamOutput(output, type: .audio, sampleHandlerQueue: queue)

        try await stream.startCapture()
        self.stream = stream
        self.output = output
        Self.log.info("SCStream started, filtering to \(Self.musicBundleID, privacy: .public)")
    }

    func stop() async {
        if let stream {
            try? await stream.stopCapture()
        }
        stream = nil
        output = nil
        Self.log.info("SCStream stopped")
    }
}

/// Bridges SCStream's `SCStreamOutput` callback (delivered on an arbitrary
/// queue) into a `@Sendable` closure. The handler runs on the SCK delivery
/// queue and must not block longer than the buffer cadence.
final class AudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onAudio: @Sendable (CMSampleBuffer) -> Void

    init(onAudio: @escaping @Sendable (CMSampleBuffer) -> Void) {
        self.onAudio = onAudio
        super.init()
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio,
              CMSampleBufferDataIsReady(sampleBuffer) else { return }
        onAudio(sampleBuffer)
    }
}

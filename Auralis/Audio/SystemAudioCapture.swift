import Accelerate
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

/// System-audio capture filtered to Music.app, with the full M2 analysis
/// pipeline (mono mix → 2048-sample Hann window @ 50% overlap → vDSP FFT
/// → log binning → bands → onset). Features stream out via `AsyncStream`.
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
        config.width = 2
        config.height = 2
        config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        config.showsCursor = false
        config.queueDepth = 5

        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        let cont = self.continuation
        let output = AudioStreamOutput(
            sampleRate: Float(config.sampleRate),
            channels: Int(config.channelCount)
        ) { features in
            cont.yield(features)
        }

        let queue = DispatchQueue(label: "app.auralis.audio.delivery",
                                  qos: .userInteractive)
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

/// Bridges `SCStreamOutput` callbacks into the analysis pipeline.
/// Owns the ring buffer, FFT, band aggregator, and onset detector; all
/// accessed exclusively from the SCK serial delivery queue.
final class AudioStreamOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let onFeatures: @Sendable (AudioFeatures) -> Void
    private let sampleRate: Float
    private let channels: Int
    private let windowSize = 2048
    private let hop = 1024

    private let fft: FFTAnalyzer
    private let logBinner: LogBinner
    private let bands: BandComputer
    private let onsets = OnsetDetector()

    private var ring: [Float]
    private var writeIndex = 0
    private var samplesSinceHop = 0
    private var hasFilled = false
    private var monoScratch: [Float] = []

    init(sampleRate: Float,
         channels: Int,
         onFeatures: @escaping @Sendable (AudioFeatures) -> Void) {
        self.sampleRate = sampleRate
        self.channels = channels
        self.onFeatures = onFeatures
        self.fft = FFTAnalyzer(windowSize: windowSize)
        self.logBinner = LogBinner(fftSize: windowSize, sampleRate: sampleRate)
        self.bands = BandComputer(sampleRate: sampleRate, fftSize: windowSize)
        self.ring = [Float](repeating: 0, count: windowSize)
        super.init()
    }

    func stream(_ stream: SCStream,
                didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        guard type == .audio, CMSampleBufferDataIsReady(sampleBuffer) else { return }
        let time = CACurrentMediaTime()
        AudioMath.withSamples(of: sampleBuffer) { abl, frames in
            guard frames > 0 else { return }
            mixMonoAndIngest(abl: abl, frames: frames, at: time)
        }
    }

    private func mixMonoAndIngest(abl: UnsafeMutableAudioBufferListPointer,
                                  frames: Int,
                                  at time: TimeInterval) {
        if monoScratch.count < frames {
            monoScratch = [Float](repeating: 0, count: frames)
        }
        monoScratch.withUnsafeMutableBufferPointer { dst in
            let base = dst.baseAddress!
            if abl.count == 1, let p = abl[0].mData?.assumingMemoryBound(to: Float.self) {
                memcpy(base, p, frames * MemoryLayout<Float>.size)
            } else if abl.count >= 2,
                      let l = abl[0].mData?.assumingMemoryBound(to: Float.self),
                      let r = abl[1].mData?.assumingMemoryBound(to: Float.self) {
                vDSP_vadd(l, 1, r, 1, base, 1, vDSP_Length(frames))
                var half: Float = 0.5
                vDSP_vsmul(base, 1, &half, base, 1, vDSP_Length(frames))
            }
        }

        monoScratch.withUnsafeBufferPointer { src in
            push(samples: src.baseAddress!, count: frames)
        }

        // Each completed hop triggers a feature emit using the current ring contents.
        while samplesSinceHop >= hop {
            samplesSinceHop -= hop
            emitWindow(at: time)
        }
    }

    private func push(samples: UnsafePointer<Float>, count: Int) {
        var remaining = count
        var srcOffset = 0
        ring.withUnsafeMutableBufferPointer { dst in
            let base = dst.baseAddress!
            while remaining > 0 {
                let chunk = min(remaining, windowSize - writeIndex)
                memcpy(base + writeIndex,
                       samples + srcOffset,
                       chunk * MemoryLayout<Float>.size)
                writeIndex = (writeIndex + chunk) % windowSize
                srcOffset += chunk
                remaining -= chunk
                samplesSinceHop += chunk
            }
        }
        if !hasFilled, samplesSinceHop >= windowSize {
            hasFilled = true
        }
    }

    private func emitWindow(at time: TimeInterval) {
        // Linearize the ring starting at the oldest sample (== writeIndex).
        var window = [Float](repeating: 0, count: windowSize)
        ring.withUnsafeBufferPointer { src in
            window.withUnsafeMutableBufferPointer { dst in
                let srcBase = src.baseAddress!
                let dstBase = dst.baseAddress!
                let head = windowSize - writeIndex
                memcpy(dstBase, srcBase + writeIndex, head * MemoryLayout<Float>.size)
                if writeIndex > 0 {
                    memcpy(dstBase + head, srcBase, writeIndex * MemoryLayout<Float>.size)
                }
            }
        }

        let rms = window.withUnsafeBufferPointer { p in
            AudioMath.rms(p.baseAddress!, count: windowSize)
        }
        let magnitudes = fft.analyze(window: window)
        let (low, mid, high) = magnitudes.withUnsafeBufferPointer { p in
            bands.compute(magnitudes: p.baseAddress!, count: magnitudes.count)
        }
        let loudness = bands.aWeightedLoudness(low: low, mid: mid, high: high)
        let logMags = magnitudes.withUnsafeBufferPointer { p in
            logBinner.bin(magnitudes: p.baseAddress!, count: magnitudes.count)
        }
        let onset = onsets.process(magnitudes: logMags, at: time)

        let features = AudioFeatures(
            level: rms,
            loudness: loudness,
            lowBand: low,
            midBand: mid,
            highBand: high,
            magnitudes: logMags,
            beat: onset.envelope,
            didBeat: onset.fired,
            bpm: onsets.bpm,
            timestamp: time
        )
        onFeatures(features)
    }
}

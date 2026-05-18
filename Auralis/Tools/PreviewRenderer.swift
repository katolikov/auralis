import AppKit
import CoreGraphics
import Foundation
import simd

/// Renders one image per visualizer mode to a target directory and exits.
/// Invoked from AuralisApp.init when `--render-previews <dir>` appears in
/// the command-line arguments. Used by `make previews` to generate the
/// gallery imagery used in the README.
@MainActor
enum PreviewRenderer {
    static func handleCommandLineIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render-previews") else {
            return false
        }
        let outputDir: URL
        if idx + 1 < args.count {
            outputDir = URL(fileURLWithPath: args[idx + 1])
        } else {
            outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/previews")
        }
        run(outputDir: outputDir)
        return true
    }

    static func run(outputDir: URL) {
        guard let renderer = OffscreenRenderer() else {
            fputs("PreviewRenderer: Metal device unavailable\n", stderr)
            exit(1)
        }

        let palettes: [VisualizerID: Theme.Snapshot] = [
            .aurora:   palette(primary: .init(0.42, 0.78, 0.96),
                               secondary: .init(0.55, 0.40, 0.92),
                               accent:    .init(0.96, 0.55, 0.82),
                               background:.init(0.020, 0.025, 0.060)),
            .bloom:    palette(primary: .init(0.96, 0.42, 0.55),
                               secondary: .init(0.95, 0.78, 0.32),
                               accent:    .init(0.98, 0.55, 0.20),
                               background:.init(0.040, 0.018, 0.020)),
            .lattice:  palette(primary: .init(0.30, 0.85, 0.78),
                               secondary: .init(0.20, 0.45, 0.85),
                               accent:    .init(0.85, 0.95, 0.40),
                               background:.init(0.012, 0.025, 0.030)),
            .filament: palette(primary: .init(0.92, 0.60, 0.95),
                               secondary: .init(0.40, 0.65, 0.95),
                               accent:    .init(1.00, 0.85, 0.40),
                               background:.init(0.020, 0.020, 0.040)),
            .halo:     palette(primary: .init(0.95, 0.72, 0.42),
                               secondary: .init(0.45, 0.35, 0.78),
                               accent:    .init(0.98, 0.55, 0.60),
                               background:.init(0.028, 0.020, 0.045))
        ]

        let magnitudes = synthesizedMagnitudes()
        renderer.uploadMagnitudes(magnitudes)
        let features = synthesizedFeatures(magnitudes: magnitudes)
        let smoothed = SmoothedFeatures(
            level: features.level,
            loudness: features.loudness,
            low: features.lowBand,
            mid: features.midBand,
            high: features.highBand,
            beat: features.beat
        )

        do {
            for mode in VisualizerID.allCases {
                let visualizer = try mode.build(device: renderer.device,
                                                format: renderer.format)
                let snapshot = palettes[mode] ?? Theme.defaultSnapshot
                let frame = VisualizerFrame(
                    time: previewTime(for: mode),
                    aspect: 16.0 / 9.0,
                    features: features,
                    smoothed: smoothed,
                    palette: snapshot,
                    magnitudesBuffer: renderer.magnitudesBuffer
                )
                guard let image = renderer.render(mode: visualizer,
                                                  frame: frame,
                                                  size: SIMD2(1920, 1080)) else {
                    fputs("PreviewRenderer: failed to render \(mode.rawValue)\n", stderr)
                    continue
                }
                let url = outputDir.appendingPathComponent("\(mode.rawValue).png")
                if OffscreenRenderer.savePNG(image, to: url) {
                    fputs("Rendered \(mode.rawValue) -> \(url.path)\n", stderr)
                }
            }
        } catch {
            fputs("PreviewRenderer error: \(error)\n", stderr)
        }
        exit(0)
    }

    private static func palette(primary: SIMD3<Float>,
                                secondary: SIMD3<Float>,
                                accent: SIMD3<Float>,
                                background: SIMD3<Float>) -> Theme.Snapshot {
        Theme.Snapshot(primary: primary,
                       secondary: secondary,
                       accent: accent,
                       background: background)
    }

    private static func synthesizedMagnitudes() -> [Float] {
        var mags = [Float](repeating: 0, count: AudioFeatures.binCount)
        for i in 0..<mags.count {
            let t = Float(i) / Float(mags.count - 1)
            // Pink-noise-ish decay, with a few peaks for variety.
            let base = 0.32 * powf(1.0 - t, 1.8)
            let peakA = expf(-powf((t - 0.12) * 9.0, 2.0)) * 0.35
            let peakB = expf(-powf((t - 0.42) * 8.0, 2.0)) * 0.22
            let peakC = expf(-powf((t - 0.72) * 11.0, 2.0)) * 0.12
            mags[i] = max(0, base + peakA + peakB + peakC)
        }
        return mags
    }

    private static func synthesizedFeatures(magnitudes: [Float]) -> AudioFeatures {
        AudioFeatures(
            level: 0.42,
            loudness: 0.36,
            lowBand: 0.32,
            midBand: 0.28,
            highBand: 0.20,
            magnitudes: magnitudes,
            beat: 0.55,
            didBeat: true,
            bpm: 118,
            timestamp: 0
        )
    }

    private static func previewTime(for mode: VisualizerID) -> Float {
        // Stage each mode at a flattering moment in its loop.
        switch mode {
        case .aurora:   return 4.2
        case .bloom:    return 2.6
        case .lattice:  return 5.3
        case .filament: return 7.1
        case .halo:     return 3.4
        }
    }
}

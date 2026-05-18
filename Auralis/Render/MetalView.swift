import MetalKit
import SwiftUI

struct MetalView: NSViewRepresentable {
    @EnvironmentObject var audio: AudioCaptureController
    @EnvironmentObject var theme: Theme
    @Binding var activeMode: VisualizerID

    func makeCoordinator() -> Renderer { Renderer() }

    func makeNSView(context: Context) -> MTKView {
        let view = MTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.preferredFramesPerSecond = 120
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        view.framebufferOnly = true
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.layer?.isOpaque = true
        view.delegate = context.coordinator
        context.coordinator.configure(view: view)
        return view
    }

    func updateNSView(_ nsView: MTKView, context: Context) {
        let r = context.coordinator
        r.features = audio.features
        r.smoothed = SmoothedFeatures(
            level: audio.smoothedLevel,
            loudness: audio.smoothedLoudness,
            low: audio.smoothedLow,
            mid: audio.smoothedMid,
            high: audio.smoothedHigh,
            beat: audio.smoothedBeat
        )
        r.palette = theme.snapshot
        r.activeMode = activeMode
    }
}

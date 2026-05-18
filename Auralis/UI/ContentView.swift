import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audio: AudioCaptureController
    @EnvironmentObject var musicKit: MusicAppObserver
    @EnvironmentObject var artwork: ArtworkLoader
    @EnvironmentObject var theme: Theme

    @State private var cursorActive = false
    @State private var cursorPosition: CGPoint = .zero
    @State private var hideTask: Task<Void, Never>?
    @State private var viewSize: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                MetalView()
                    .ignoresSafeArea()

                statusOverlay
                    .padding(.top, 28)
                    .padding(.leading, 28)
                    .opacity(cursorActive ? 1 : 0.35)

                if audio.showDebugHUD {
                    VStack {
                        Spacer().frame(height: 28)
                        HStack {
                            Spacer()
                            DebugHUD()
                                .transition(AnyTransition.opacity
                                    .combined(with: AnyTransition.scale(scale: 0.97)))
                                .padding(.trailing, 28)
                        }
                        Spacer()
                    }
                }

                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 16) {
                        NowPlayingOverlay(
                            track: musicKit.nowPlaying,
                            artwork: artwork.image,
                            cursorLocation: cursorPosition,
                            viewSize: viewSize
                        )
                        .opacity(cursorActive ? 1 : 0)
                        .scaleEffect(cursorActive ? 1 : 0.99, anchor: .bottomLeading)

                        Spacer()

                        bottomMeter
                            .opacity(cursorActive ? 1 : 0.45)
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
                }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let pt):
                    cursorPosition = pt
                    if !cursorActive { cursorActive = true }
                    armHideTask()
                case .ended:
                    armHideTask(delay: 0.4)
                }
            }
            .onAppear {
                viewSize = geo.size
            }
            .onChange(of: geo.size) { _, newSize in
                viewSize = newSize
            }
            .animation(.easeInOut(duration: 0.22), value: cursorActive)
            .animation(.easeInOut(duration: 0.18), value: audio.showDebugHUD)
        }
    }

    private func armHideTask(delay: TimeInterval = 2.5) {
        hideTask?.cancel()
        hideTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            cursorActive = false
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                let statusColor: Color = audio.isRunning ? theme.primary : .orange
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
                Text("Auralis · Milestone 3")
                    .font(.system(size: 12, weight: .medium))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.78))
            }

            if let status = audio.statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.78))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var bottomMeter: some View {
        HStack(spacing: 14) {
            Text("LEVEL")
                .font(.system(size: 9, weight: .semibold))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.55))
            AudioLevelBar(level: audio.smoothedLevel,
                          gradient: [theme.primary, theme.secondary])
                .frame(width: 240, height: 6)
            Text(String(format: "%.2f", audio.smoothedLevel))
                .font(.system(size: 10, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct AudioLevelBar: View {
    let level: Float
    let gradient: [Color]
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))
                Capsule(style: .continuous)
                    .fill(LinearGradient(colors: gradient,
                                         startPoint: .leading,
                                         endPoint: .trailing))
                    .frame(width: max(2, geo.size.width * clamped))
                    .animation(.linear(duration: 0.05), value: clamped)
            }
        }
    }
    private var clamped: CGFloat {
        CGFloat(min(1, max(0, level * 6)))
    }
}

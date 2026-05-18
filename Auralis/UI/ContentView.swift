import SwiftUI

struct ContentView: View {
    @EnvironmentObject var audio: AudioCaptureController

    var body: some View {
        ZStack(alignment: .topLeading) {
            MetalView()
                .ignoresSafeArea()

            statusOverlay
                .padding(.top, 28)
                .padding(.leading, 28)

            VStack {
                Spacer()
                bottomMeter
                    .padding(.horizontal, 28)
                    .padding(.bottom, 28)
            }
        }
    }

    @ViewBuilder
    private var statusOverlay: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                let statusColor: Color = audio.isRunning ? .green : .orange
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .shadow(color: statusColor.opacity(0.6), radius: 4)
                Text("Auralis · Milestone 1")
                    .font(.system(size: 12, weight: .medium, design: .default))
                    .tracking(0.6)
                    .foregroundStyle(.white.opacity(0.78))
            }

            if let status = audio.statusMessage {
                Text(status)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial,
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    @ViewBuilder
    private var bottomMeter: some View {
        HStack(spacing: 16) {
            Text("LEVEL")
                .font(.system(size: 10, weight: .semibold, design: .default))
                .tracking(2.0)
                .foregroundStyle(.white.opacity(0.55))

            AudioLevelBar(level: audio.smoothedLevel)
                .frame(height: 6)

            Text(String(format: "%.2f", audio.smoothedLevel))
                .font(.system(size: 11, weight: .regular, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 44, alignment: .trailing)
        }
        .frame(maxWidth: 480)
    }
}

private struct AudioLevelBar: View {
    let level: Float

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.08))

                Capsule(style: .continuous)
                    .fill(LinearGradient(
                        colors: [Color(red: 0.40, green: 0.78, blue: 1.00),
                                 Color(red: 0.55, green: 0.45, blue: 1.00)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ))
                    .frame(width: max(2, geo.size.width * clamped))
                    .animation(.linear(duration: 0.05), value: clamped)
            }
        }
    }

    private var clamped: CGFloat {
        CGFloat(min(1, max(0, level * 6)))
    }
}

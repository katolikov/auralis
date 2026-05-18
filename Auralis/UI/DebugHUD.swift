import SwiftUI

struct DebugHUD: View {
    @EnvironmentObject var audio: AudioCaptureController

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            VStack(alignment: .leading, spacing: 6) {
                row(label: "LEVEL", value: audio.smoothedLevel)
                row(label: "LOUD", value: audio.smoothedLoudness)
                row(label: "LOW", value: audio.smoothedLow, tint: .orange)
                row(label: "MID", value: audio.smoothedMid, tint: .green)
                row(label: "HIGH", value: audio.smoothedHigh, tint: .cyan)
            }

            SpectrumBars(magnitudes: audio.features.magnitudes)
                .frame(width: 280, height: 72)
                .padding(.top, 6)
        }
        .padding(14)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        )
        .frame(width: 320)
    }

    @ViewBuilder
    private var header: some View {
        HStack(spacing: 10) {
            Text("DEBUG · HUD")
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.8)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text("BPM \(Int(audio.bpm.rounded()))")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.55))
            Circle()
                .fill(.white)
                .opacity(Double(audio.smoothedBeat))
                .frame(width: 7, height: 7)
        }
    }

    private func row(label: String, value: Float, tint: Color = .white) -> some View {
        HStack(spacing: 10) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .tracking(1.5)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 42, alignment: .leading)
            MeterBar(value: value, tint: tint)
                .frame(height: 4)
            Text(String(format: "%.2f", value))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct MeterBar: View {
    let value: Float
    let tint: Color
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.08))
                Capsule(style: .continuous)
                    .fill(tint.opacity(0.85))
                    .frame(width: max(2, geo.size.width * CGFloat(min(1, max(0, value * 6)))))
            }
        }
    }
}

private struct SpectrumBars: View {
    let magnitudes: [Float]

    var body: some View {
        GeometryReader { geo in
            let count = magnitudes.count
            let gap: CGFloat = 1.5
            let barWidth = max(1, (geo.size.width - CGFloat(count - 1) * gap) / CGFloat(count))
            HStack(alignment: .bottom, spacing: gap) {
                ForEach(0..<count, id: \.self) { i in
                    let v = CGFloat(min(1, max(0, magnitudes[i] * 14)))
                    Capsule(style: .continuous)
                        .fill(LinearGradient(colors: [
                            Color(red: 0.40, green: 0.78, blue: 1.00),
                            Color(red: 0.65, green: 0.40, blue: 0.95)
                        ], startPoint: .bottom, endPoint: .top))
                        .frame(width: barWidth,
                               height: max(2, v * geo.size.height))
                }
            }
        }
    }
}

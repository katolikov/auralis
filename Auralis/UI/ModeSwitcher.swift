import SwiftUI

struct ModeSwitcher: View {
    @Binding var active: VisualizerID
    @EnvironmentObject var theme: Theme

    var body: some View {
        HStack(spacing: 2) {
            ForEach(VisualizerID.allCases) { mode in
                Button {
                    active = mode
                } label: {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                            .font(.system(size: 11, weight: .semibold))
                            .tracking(0.4)
                        if active == mode {
                            Text(modifierString(mode))
                                .font(.system(size: 9, weight: .medium, design: .monospaced))
                                .opacity(0.65)
                        }
                    }
                    .foregroundStyle(active == mode ? Color.white : Color.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(active == mode ? activeFill : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .help("\(mode.displayName) · \(mode.tagline)")
            }
        }
        .padding(3)
        .background(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .fill(.ultraThinMaterial.opacity(0.85))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .stroke(.white.opacity(0.06), lineWidth: 1)
        )
        .animation(.easeOut(duration: 0.18), value: active)
    }

    private var activeFill: Color {
        theme.primary.opacity(0.32)
    }

    private func modifierString(_ mode: VisualizerID) -> String {
        // KeyEquivalent for digits — just show the digit.
        let s = String(describing: mode.shortcut)
        return "⌘\(s.last.map(String.init) ?? "1")"
    }
}

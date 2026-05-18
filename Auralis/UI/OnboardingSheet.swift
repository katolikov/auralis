import AppKit
import CoreGraphics
import SwiftUI

struct OnboardingSheet: View {
    @Binding var isPresented: Bool
    @EnvironmentObject var theme: Theme
    @State private var screenRecordingGranted: Bool = CGPreflightScreenCaptureAccess()
    @State private var musicLaunched: Bool = false

    var body: some View {
        ZStack {
            LinearGradient(colors: [
                theme.background,
                theme.background.opacity(0.7),
                Color.black
            ], startPoint: .topLeading, endPoint: .bottomTrailing)
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header
                    .padding(.top, 48)
                    .padding(.bottom, 32)

                VStack(spacing: 14) {
                    permissionCard(
                        icon: "rectangle.dashed.badge.record",
                        title: "Screen Recording",
                        subtitle: "ScreenCaptureKit needs this permission to capture system audio. Auralis filters its capture to the Music app's bundle id — no screen content is recorded.",
                        granted: screenRecordingGranted,
                        cta: screenRecordingGranted ? "Granted" : "Open System Settings"
                    ) {
                        guard !screenRecordingGranted else { return }
                        _ = CGRequestScreenCaptureAccess()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            screenRecordingGranted = CGPreflightScreenCaptureAccess()
                        }
                    }

                    permissionCard(
                        icon: "music.note",
                        title: "Apple Music",
                        subtitle: "Auralis listens for the Music app's now-playing notification and reads broadband artwork from the iTunes catalog. Start playback in Music to wake the visualizer.",
                        granted: musicLaunched,
                        cta: musicLaunched ? "Launched" : "Open Music"
                    ) {
                        launchMusic()
                        musicLaunched = true
                    }
                }
                .padding(.horizontal, 36)

                Spacer()

                HStack(spacing: 14) {
                    Button {
                        isPresented = false
                    } label: {
                        Text("Skip for now")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)

                    Button {
                        isPresented = false
                    } label: {
                        Text("Start Visualizing")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 22)
                            .padding(.vertical, 10)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(theme.primary.opacity(0.85))
                            )
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.defaultAction)
                }
                .padding(.bottom, 36)
            }
        }
        .frame(width: 560, height: 540)
    }

    @ViewBuilder
    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [theme.primary, theme.secondary],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 64, height: 64)
                    .shadow(color: theme.primary.opacity(0.5), radius: 22, y: 6)
                Image(systemName: "waveform")
                    .font(.system(size: 26, weight: .medium))
                    .foregroundStyle(.white)
            }

            Text("Welcome to Auralis")
                .font(.system(size: 24, weight: .semibold))
                .tracking(-0.4)
                .foregroundStyle(.white)

            Text("Two quick permissions and the visualizer wakes up.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    @ViewBuilder
    private func permissionCard(icon: String,
                                title: String,
                                subtitle: String,
                                granted: Bool,
                                cta: String,
                                action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(theme.primary.opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(theme.primary)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                    if granted {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .font(.system(size: 12))
                    }
                }
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: action) {
                Text(cta)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(
                        Capsule(style: .continuous)
                            .fill(granted ? .green.opacity(0.6) : theme.primary.opacity(0.7))
                    )
            }
            .buttonStyle(.plain)
            .disabled(granted && cta != "Open Music")
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(.white.opacity(0.07), lineWidth: 1)
        )
    }

    private func launchMusic() {
        let candidates = [
            URL(fileURLWithPath: "/System/Applications/Music.app"),
            URL(fileURLWithPath: "/Applications/Music.app")
        ]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: url, configuration: config)
            return
        }
    }
}

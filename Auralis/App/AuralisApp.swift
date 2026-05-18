import AppKit
import SwiftUI

@main
struct AuralisApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var audio = AudioCaptureController()
    @StateObject private var musicKit = MusicAppObserver()
    @StateObject private var artwork = ArtworkLoader()
    @StateObject private var theme = Theme()
    @StateObject private var menuBar = MenuBarController()

    var body: some Scene {
        WindowGroup("Auralis") {
            ContentView()
                .environmentObject(appState)
                .environmentObject(audio)
                .environmentObject(musicKit)
                .environmentObject(artwork)
                .environmentObject(theme)
                .frame(minWidth: 720, minHeight: 480)
                .background(Color.black)
                .task {
                    menuBar.install(musicKit: musicKit, appState: appState)
                    await audio.start()
                    await musicKit.start()
                }
                .onChange(of: musicKit.nowPlaying) { _, track in
                    artwork.load(url: track?.artworkURL)
                }
                .onChange(of: artwork.palette) { _, palette in
                    theme.update(from: palette)
                }
                .sheet(isPresented: $appState.isOnboardingActive,
                       onDismiss: { appState.dismissOnboarding() }) {
                    OnboardingSheet(isPresented: $appState.isOnboardingActive)
                        .environmentObject(theme)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .windowArrangement) {
                Button("Enter Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
            CommandMenu("Visualizer") {
                ForEach(VisualizerID.allCases) { mode in
                    Button(mode.displayName) {
                        appState.activeMode = mode
                    }
                    .keyboardShortcut(mode.shortcut, modifiers: .command)
                }
                Divider()
                Button("Next Mode") { appState.cycleMode() }
                    .keyboardShortcut(.rightArrow, modifiers: [.command, .option])
                Button("Previous Mode") { appState.cycleMode(reverse: true) }
                    .keyboardShortcut(.leftArrow, modifiers: [.command, .option])
                Divider()
                Button("Toggle Debug HUD") { audio.toggleDebugHUD() }
                    .keyboardShortcut("d", modifiers: .command)
            }
        }
    }
}

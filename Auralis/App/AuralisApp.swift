import SwiftUI

@main
struct AuralisApp: App {
    @StateObject private var appState = AppState()
    @StateObject private var audio = AudioCaptureController()
    @StateObject private var musicKit = MusicAppObserver()
    @StateObject private var artwork = ArtworkLoader()
    @StateObject private var theme = Theme()

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
                    await audio.start()
                    await musicKit.start()
                }
                .onChange(of: musicKit.nowPlaying) { _, track in
                    artwork.load(url: track?.artworkURL)
                }
                .onChange(of: artwork.palette) { _, palette in
                    theme.update(from: palette)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
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

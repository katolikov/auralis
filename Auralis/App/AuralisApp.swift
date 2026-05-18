import SwiftUI

@main
struct AuralisApp: App {
    @StateObject private var audio = AudioCaptureController()
    @StateObject private var musicKit = MusicAppObserver()
    @StateObject private var artwork = ArtworkLoader()
    @StateObject private var theme = Theme()

    var body: some Scene {
        WindowGroup("Auralis") {
            ContentView()
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
            CommandMenu("View") {
                Button("Toggle Debug HUD") {
                    audio.toggleDebugHUD()
                }
                .keyboardShortcut("d", modifiers: .command)
            }
        }
    }
}

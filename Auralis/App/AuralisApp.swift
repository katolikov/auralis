import SwiftUI

@main
struct AuralisApp: App {
    @StateObject private var audio = AudioCaptureController()

    var body: some Scene {
        WindowGroup("Auralis") {
            ContentView()
                .environmentObject(audio)
                .frame(minWidth: 720, minHeight: 480)
                .background(Color.black)
                .task { await audio.start() }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1280, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

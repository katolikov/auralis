import AppKit
import Combine
import Foundation

@MainActor
final class MenuBarController: ObservableObject {
    private var statusItem: NSStatusItem?
    private var cancellables = Set<AnyCancellable>()
    private weak var musicKit: MusicAppObserver?
    private weak var appState: AppState?

    func install(musicKit: MusicAppObserver, appState: AppState) {
        self.musicKit = musicKit
        self.appState = appState

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "waveform",
                                   accessibilityDescription: "Auralis")
            button.image?.isTemplate = true
        }
        statusItem = item
        rebuildMenu()

        musicKit.$nowPlaying
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
        appState.$activeMode
            .sink { [weak self] _ in self?.rebuildMenu() }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        menu.autoenablesItems = false

        if let track = musicKit?.nowPlaying {
            let titleItem = NSMenuItem(title: track.title, action: nil, keyEquivalent: "")
            titleItem.isEnabled = false
            menu.addItem(titleItem)
            let artist = track.artist.isEmpty ? "Unknown Artist" : track.artist
            let artistItem = NSMenuItem(title: artist, action: nil, keyEquivalent: "")
            artistItem.isEnabled = false
            menu.addItem(artistItem)
        } else {
            let placeholder = NSMenuItem(title: "Not playing", action: nil, keyEquivalent: "")
            placeholder.isEnabled = false
            menu.addItem(placeholder)
        }
        menu.addItem(.separator())

        if let active = appState?.activeMode {
            let modeItem = NSMenuItem(title: "Mode: \(active.displayName)", action: nil, keyEquivalent: "")
            modeItem.isEnabled = false
            menu.addItem(modeItem)
        }

        let openItem = NSMenuItem(title: "Open Auralis",
                                  action: #selector(openAuralis),
                                  keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        let quitItem = NSMenuItem(title: "Quit Auralis",
                                  action: #selector(quitApp),
                                  keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func openAuralis() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }
}

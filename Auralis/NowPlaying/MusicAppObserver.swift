import AppKit
import Foundation
import OSLog

/// Now-playing observer for the macOS Music app.
///
/// MusicKit's `SystemMusicPlayer` is iOS-only, so on macOS we listen to
/// the public `com.apple.Music.playerInfo` distributed notification (the
/// same one Music app has emitted since the iTunes days) for metadata,
/// and fall back to the iTunes Search API to resolve artwork URLs.
@MainActor
final class MusicAppObserver: ObservableObject {
    private static let log = Logger(subsystem: "app.auralis", category: "MusicApp")
    private static let notificationName = Notification.Name("com.apple.Music.playerInfo")

    @Published private(set) var nowPlaying: NowPlayingTrack?
    @Published private(set) var isPlaying = false
    @Published private(set) var hasReceivedEvent = false

    private var observer: (any NSObjectProtocol)?
    private var artworkTask: Task<Void, Never>?

    func start() async {
        let center = DistributedNotificationCenter.default()
        observer = center.addObserver(
            forName: Self.notificationName,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Already on .main (queue: .main). Read and dispatch synchronously
            // to avoid sending non-Sendable userInfo across a Task boundary.
            let payload = NowPlayingPayload(userInfo: note.userInfo)
            MainActor.assumeIsolated {
                self?.handle(payload: payload)
            }
        }
    }

    func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        observer = nil
        artworkTask?.cancel()
        artworkTask = nil
    }

    private func handle(payload: NowPlayingPayload) {
        hasReceivedEvent = true
        isPlaying = payload.isPlaying

        guard let title = payload.title, !title.isEmpty else { return }
        let artist = payload.artist ?? ""

        if nowPlaying?.title == title, nowPlaying?.artist == artist {
            return
        }

        var track = NowPlayingTrack(
            title: title,
            artist: artist,
            album: payload.album,
            artworkURL: nil
        )
        nowPlaying = track

        artworkTask?.cancel()
        artworkTask = Task { @MainActor [weak self] in
            guard let url = await ITunesSearch.artworkURL(title: title, artist: artist) else {
                return
            }
            guard let self else { return }
            if self.nowPlaying?.title == title, self.nowPlaying?.artist == artist {
                track.artworkURL = url
                self.nowPlaying = track
            }
        }
    }
}

private struct NowPlayingPayload: Sendable {
    let title: String?
    let artist: String?
    let album: String?
    let isPlaying: Bool

    init(userInfo: [AnyHashable: Any]?) {
        self.title = userInfo?["Name"] as? String
        self.artist = userInfo?["Artist"] as? String
        self.album = userInfo?["Album"] as? String
        let state = userInfo?["Player State"] as? String ?? "Playing"
        self.isPlaying = (state == "Playing")
    }
}

enum ITunesSearch {
    struct Response: Decodable {
        let results: [Item]
        struct Item: Decodable {
            let artworkUrl100: String?
        }
    }

    static func artworkURL(title: String, artist: String) async -> URL? {
        let term = "\(artist) \(title)"
        guard let encoded = term.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed),
              let endpoint = URL(string:
                "https://itunes.apple.com/search?term=\(encoded)&entity=song&limit=1")
        else { return nil }
        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = 6
            let (data, _) = try await URLSession.shared.data(for: request)
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard let small = response.results.first?.artworkUrl100 else { return nil }
            let large = small.replacingOccurrences(of: "100x100bb", with: "600x600bb")
            return URL(string: large)
        } catch {
            return nil
        }
    }
}

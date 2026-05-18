import Foundation

struct NowPlayingTrack: Sendable, Equatable {
    var title: String
    var artist: String
    var album: String?
    var artworkURL: URL?

    static let placeholder = NowPlayingTrack(
        title: "Auralis",
        artist: "Play something in Music",
        album: nil,
        artworkURL: nil
    )
}

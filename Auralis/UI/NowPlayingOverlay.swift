import SwiftUI

struct NowPlayingOverlay: View {
    @EnvironmentObject var theme: Theme
    let track: NowPlayingTrack?
    let artwork: NSImage?
    let cursorLocation: CGPoint
    let viewSize: CGSize

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            artworkTile
            trackInfo
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 16)
        .frame(width: 360, alignment: .leading)
        .background(.ultraThinMaterial.opacity(0.85),
                    in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 22, x: 0, y: 14)
    }

    @ViewBuilder
    private var artworkTile: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(colors: [theme.primary, theme.secondary],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                Image(systemName: "music.note")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
        .frame(width: 64, height: 64)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: .black.opacity(0.45), radius: 10, y: 4)
        .offset(parallaxOffset)
        .animation(.spring(response: 0.6, dampingFraction: 0.85), value: parallaxOffset)
    }

    @ViewBuilder
    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(.system(size: 15, weight: .semibold))
                .tracking(-0.3)
                .foregroundStyle(.white)
                .lineLimit(1)
            Text(displayArtist)
                .font(.system(size: 12, weight: .regular))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)
            if let album = track?.album, !album.isEmpty {
                Text(album)
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var displayTitle: String {
        let t = track?.title ?? ""
        return t.isEmpty ? NowPlayingTrack.placeholder.title : t
    }

    private var displayArtist: String {
        let a = track?.artist ?? ""
        return a.isEmpty ? NowPlayingTrack.placeholder.artist : a
    }

    private var parallaxOffset: CGSize {
        guard viewSize.width > 0, viewSize.height > 0 else { return .zero }
        let nx = (cursorLocation.x / viewSize.width) - 0.5
        let ny = (cursorLocation.y / viewSize.height) - 0.5
        return CGSize(width: nx * -8, height: ny * -8)
    }
}

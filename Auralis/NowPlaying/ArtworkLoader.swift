import AppKit
import Foundation
import OSLog
import simd

@MainActor
final class ArtworkLoader: ObservableObject {
    private static let log = Logger(subsystem: "app.auralis", category: "Artwork")

    @Published private(set) var image: NSImage?
    @Published private(set) var palette: [SIMD3<Float>] = []

    private var loadTask: Task<Void, Never>?
    private var currentURL: URL?
    private let extractor = PaletteExtractor()

    func load(url: URL?) {
        guard url != currentURL else { return }
        currentURL = url
        loadTask?.cancel()

        guard let url else {
            image = nil
            palette = []
            return
        }

        let extractor = self.extractor
        loadTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                guard !Task.isCancelled else { return }
                guard let nsImage = NSImage(data: data) else { return }
                let cgImage = nsImage.cgImage(forProposedRect: nil,
                                              context: nil,
                                              hints: nil)
                let palette = cgImage.map { extractor.extract(from: $0) } ?? []

                await MainActor.run {
                    guard let self else { return }
                    self.image = nsImage
                    self.palette = palette
                }
            } catch {
                Self.log.notice("Artwork load failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

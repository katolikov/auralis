import SwiftUI
import simd

/// Palette → SwiftUI Colors + shader uniforms. Smoothly interpolates
/// toward each new artwork palette so the visual register glides between
/// tracks rather than snapping.
@MainActor
final class Theme: ObservableObject {
    struct Snapshot: Sendable, Equatable {
        var primary: SIMD3<Float>
        var secondary: SIMD3<Float>
        var accent: SIMD3<Float>
        var background: SIMD3<Float>
    }

    static let defaultSnapshot = Snapshot(
        primary: SIMD3<Float>(0.45, 0.65, 0.95),
        secondary: SIMD3<Float>(0.95, 0.55, 0.78),
        accent: SIMD3<Float>(0.30, 0.85, 0.85),
        background: SIMD3<Float>(0.020, 0.030, 0.055)
    )

    @Published private(set) var snapshot: Snapshot = Theme.defaultSnapshot
    private var target: Snapshot = Theme.defaultSnapshot
    private var ticker: Task<Void, Never>?
    private let interpolation: Float = 0.06

    var primary: Color { snapshot.primary.color }
    var secondary: Color { snapshot.secondary.color }
    var accent: Color { snapshot.accent.color }
    var background: Color { snapshot.background.color }

    init() {
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                self?.step()
                try? await Task.sleep(for: .milliseconds(33))
            }
        }
    }

    deinit {
        ticker?.cancel()
    }

    func update(from extracted: [SIMD3<Float>]) {
        guard !extracted.isEmpty else {
            target = Self.defaultSnapshot
            return
        }
        let primary = extracted.first ?? Self.defaultSnapshot.primary
        let secondary = extracted.dropFirst().first ?? primary
        let accent = extracted.dropFirst(2).first ?? secondary

        // Background: darkest extracted, deepened toward black.
        let darkest = extracted.min { lum($0) < lum($1) }
            ?? Self.defaultSnapshot.background
        let background = mix(darkest, .zero, 0.82) + SIMD3<Float>(0.012, 0.014, 0.022)

        target = Snapshot(
            primary: saturate(primary),
            secondary: saturate(secondary),
            accent: saturate(accent),
            background: background
        )
    }

    private func step() {
        let next = Snapshot(
            primary: mix(snapshot.primary, target.primary, interpolation),
            secondary: mix(snapshot.secondary, target.secondary, interpolation),
            accent: mix(snapshot.accent, target.accent, interpolation),
            background: mix(snapshot.background, target.background, interpolation)
        )
        if next != snapshot {
            snapshot = next
        }
    }

    private func lum(_ c: SIMD3<Float>) -> Float {
        0.299 * c.x + 0.587 * c.y + 0.114 * c.z
    }

    private func saturate(_ c: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(min(1, max(0, c.x)),
                     min(1, max(0, c.y)),
                     min(1, max(0, c.z)))
    }

    private func mix(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float) -> SIMD3<Float> {
        a + (b - a) * t
    }
}

extension SIMD3 where Scalar == Float {
    var color: Color {
        Color(.sRGB,
              red: Double(x),
              green: Double(y),
              blue: Double(z),
              opacity: 1)
    }
}

import Foundation
import Metal
import SwiftUI
import simd

enum VisualizerID: String, CaseIterable, Identifiable, Sendable {
    case aurora
    case bloom
    case lattice
    case filament
    case halo

    var id: String { rawValue }

    var displayName: String {
        rawValue.prefix(1).uppercased() + rawValue.dropFirst()
    }

    var shortcut: KeyEquivalent {
        switch self {
        case .aurora:   return "1"
        case .bloom:    return "2"
        case .lattice:  return "3"
        case .filament: return "4"
        case .halo:     return "5"
        }
    }

    var tagline: String {
        switch self {
        case .aurora:   return "Northern lights, liquid glass"
        case .bloom:    return "Metaball field, beat shockwaves"
        case .lattice:  return "Instanced grid, FFT heightmap"
        case .filament: return "250k particles, curl-noise flow"
        case .halo:     return "Minimal editorial torus"
        }
    }
}

struct SmoothedFeatures: Sendable {
    var level: Float
    var loudness: Float
    var low: Float
    var mid: Float
    var high: Float
    var beat: Float
}

struct VisualizerFrame {
    var time: Float
    var aspect: Float
    var features: AudioFeatures
    var smoothed: SmoothedFeatures
    var palette: Theme.Snapshot
    var magnitudesBuffer: any MTLBuffer
}

@MainActor
protocol VisualizerMode: AnyObject {
    static var id: VisualizerID { get }
    init(device: any MTLDevice, format: MTLPixelFormat) throws
    func encode(into encoder: any MTLRenderCommandEncoder, frame: VisualizerFrame)
}

extension VisualizerMode {
    var id: VisualizerID { Self.id }
}

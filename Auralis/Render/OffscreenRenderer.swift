import CoreGraphics
import Foundation
import ImageIO
import Metal
import UniformTypeIdentifiers
import simd

/// Headless render utility used by tests and the preview-image tool.
/// One instance owns its Metal device, command queue, and a magnitudes
/// buffer shared across `VisualizerFrame`s.
@MainActor
final class OffscreenRenderer {
    let device: any MTLDevice
    let commandQueue: any MTLCommandQueue
    let format: MTLPixelFormat = .bgra8Unorm
    private(set) var magnitudesBuffer: any MTLBuffer

    init?() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.commandQueue = queue
        let stride = MemoryLayout<Float>.stride * AudioFeatures.binCount
        guard let buffer = device.makeBuffer(length: stride, options: .storageModeShared) else {
            return nil
        }
        buffer.label = "Offscreen.magnitudes"
        self.magnitudesBuffer = buffer
    }

    func uploadMagnitudes(_ values: [Float]) {
        let count = min(values.count, AudioFeatures.binCount)
        values.withUnsafeBufferPointer { src in
            _ = memcpy(magnitudesBuffer.contents(),
                       src.baseAddress!,
                       count * MemoryLayout<Float>.stride)
        }
    }

    func render(mode: any VisualizerMode,
                frame: VisualizerFrame,
                size: SIMD2<Int>) -> CGImage? {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: format,
            width: size.x,
            height: size.y,
            mipmapped: false
        )
        descriptor.usage = [.renderTarget, .shaderRead]
        guard let texture = device.makeTexture(descriptor: descriptor) else { return nil }

        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = texture
        pass.colorAttachments[0].loadAction = .clear
        let bg = frame.palette.background
        pass.colorAttachments[0].clearColor = MTLClearColor(
            red: Double(bg.x),
            green: Double(bg.y),
            blue: Double(bg.z),
            alpha: 1
        )
        pass.colorAttachments[0].storeAction = .store

        guard let command = commandQueue.makeCommandBuffer(),
              let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return nil }
        mode.encode(into: encoder, frame: frame)
        encoder.endEncoding()
        command.commit()
        command.waitUntilCompleted()

        let bytesPerRow = size.x * 4
        var bgra = [UInt8](repeating: 0, count: bytesPerRow * size.y)
        texture.getBytes(&bgra,
                         bytesPerRow: bytesPerRow,
                         from: MTLRegionMake2D(0, 0, size.x, size.y),
                         mipmapLevel: 0)

        // Swap BGRA → RGBA for downstream CG/ImageIO consumers.
        for i in stride(from: 0, to: bgra.count, by: 4) {
            let blue = bgra[i]
            bgra[i] = bgra[i + 2]
            bgra[i + 2] = blue
        }

        guard let provider = CGDataProvider(data: Data(bgra) as CFData) else {
            return nil
        }
        return CGImage(
            width: size.x,
            height: size.y,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: CGColorSpace(name: CGColorSpace.sRGB)
                ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue:
                CGImageAlphaInfo.premultipliedLast.rawValue |
                CGBitmapInfo.byteOrder32Big.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    @discardableResult
    static func savePNG(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1, nil
        ) else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}

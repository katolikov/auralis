import AppKit
import CoreGraphics
import Foundation
import ImageIO

/// `--render-icon <dir>` mode. Draws the macOS AppIcon set procedurally
/// in CoreGraphics — squircle background with an aurora gradient,
/// centered halo ring, accent dot, and a circle of sparkles. Outputs
/// every PNG the AppIcon.appiconset requires, named to match.
enum IconRenderer {
    static func handleCommandLineIfNeeded() -> Bool {
        let args = CommandLine.arguments
        guard let idx = args.firstIndex(of: "--render-icon") else { return false }
        let outputDir: URL
        if idx + 1 < args.count {
            outputDir = URL(fileURLWithPath: args[idx + 1])
        } else {
            outputDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                .appendingPathComponent("docs/icon")
        }
        run(outputDir: outputDir)
        return true
    }

    static func run(outputDir: URL) {
        try? FileManager.default.createDirectory(
            at: outputDir,
            withIntermediateDirectories: true
        )

        let renditions: [(Int, String)] = [
            (16,   "icon_16x16.png"),
            (32,   "icon_16x16@2x.png"),
            (32,   "icon_32x32.png"),
            (64,   "icon_32x32@2x.png"),
            (128,  "icon_128x128.png"),
            (256,  "icon_128x128@2x.png"),
            (256,  "icon_256x256.png"),
            (512,  "icon_256x256@2x.png"),
            (512,  "icon_512x512.png"),
            (1024, "icon_512x512@2x.png")
        ]

        for (size, name) in renditions {
            guard let image = drawIcon(size: size) else {
                fputs("IconRenderer: failed to draw \(size)\n", stderr)
                continue
            }
            let url = outputDir.appendingPathComponent(name)
            if savePNG(image, to: url) {
                fputs("Wrote \(name) (\(size)x\(size)) -> \(url.path)\n", stderr)
            }
        }
        exit(0)
    }

    private static func drawIcon(size: Int) -> CGImage? {
        let s = CGFloat(size)
        let cs = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil,
            width: size, height: size,
            bitsPerComponent: 8, bytesPerRow: 0,
            space: cs,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // Anti-aliasing on for sub-pixel sparkles and ring edge.
        ctx.setShouldAntialias(true)
        ctx.interpolationQuality = .high

        // Squircle-ish clip (macOS uses ~22.5% corner radius on Big Sur+).
        let cornerRadius = s * 0.225
        let clipPath = CGPath(
            roundedRect: CGRect(x: 0, y: 0, width: s, height: s),
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )
        ctx.addPath(clipPath)
        ctx.clip()

        // Background gradient — deep aurora palette, corner-to-corner.
        let bgColors = [
            cgColor(0.045, 0.038, 0.140),
            cgColor(0.130, 0.075, 0.310),
            cgColor(0.345, 0.180, 0.560),
            cgColor(0.560, 0.395, 0.910)
        ] as CFArray
        if let bg = CGGradient(colorsSpace: cs,
                               colors: bgColors,
                               locations: [0, 0.40, 0.75, 1.0]) {
            ctx.drawLinearGradient(
                bg,
                start: CGPoint(x: 0, y: s),
                end: CGPoint(x: s, y: 0),
                options: []
            )
        }

        // Soft pink-into-cyan center glow.
        let glowColors = [
            cgColor(0.985, 0.560, 0.820, alpha: 0.55),
            cgColor(0.420, 0.780, 0.960, alpha: 0.18),
            cgColor(0.420, 0.780, 0.960, alpha: 0.0)
        ] as CFArray
        if let glow = CGGradient(colorsSpace: cs,
                                 colors: glowColors,
                                 locations: [0, 0.55, 1]) {
            ctx.drawRadialGradient(
                glow,
                startCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                startRadius: 0,
                endCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                endRadius: s * 0.58,
                options: []
            )
        }

        // Halo torus — the on-brand reference to the Halo visualizer.
        let inset = s * 0.225
        let ringRect = CGRect(
            x: inset, y: inset,
            width: s - 2 * inset, height: s - 2 * inset
        )
        let lineWidth = max(1.5, s * 0.038)
        ctx.setLineWidth(lineWidth)
        ctx.setStrokeColor(cgColor(0.97, 0.93, 1.0, alpha: 0.95))
        ctx.addEllipse(in: ringRect)
        ctx.strokePath()

        // Inside the ring, a soft inner darkening to give the torus depth.
        if size >= 32 {
            ctx.saveGState()
            let innerRect = ringRect.insetBy(dx: lineWidth, dy: lineWidth)
            ctx.addEllipse(in: innerRect)
            ctx.clip()
            let inner = [
                cgColor(0.05, 0.04, 0.18, alpha: 0.0),
                cgColor(0.05, 0.04, 0.18, alpha: 0.45)
            ] as CFArray
            if let g = CGGradient(colorsSpace: cs, colors: inner, locations: [0, 1]) {
                ctx.drawRadialGradient(
                    g,
                    startCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                    startRadius: 0,
                    endCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                    endRadius: innerRect.width * 0.6,
                    options: []
                )
            }
            ctx.restoreGState()
        }

        // Accent dot — sits dead-center, matches palette accent.
        let dot = s * 0.085
        ctx.setFillColor(cgColor(0.985, 0.560, 0.820))
        ctx.addEllipse(in: CGRect(
            x: s * 0.5 - dot * 0.5,
            y: s * 0.5 - dot * 0.5,
            width: dot, height: dot
        ))
        ctx.fillPath()

        // Tiny halo for the accent dot.
        if size >= 64 {
            let haloDot = dot * 2.4
            ctx.setFillColor(cgColor(0.985, 0.560, 0.820, alpha: 0.18))
            ctx.addEllipse(in: CGRect(
                x: s * 0.5 - haloDot * 0.5,
                y: s * 0.5 - haloDot * 0.5,
                width: haloDot, height: haloDot
            ))
            ctx.fillPath()
        }

        // Eight sparkles arranged around the torus — skip at tiny sizes.
        if size >= 64 {
            let r = s * 0.34
            let sparkle = max(1.5, s * 0.012)
            for i in 0..<8 {
                let theta = (Double(i) / 8.0) * 2 * .pi + 0.18
                let x = s * 0.5 + r * CGFloat(cos(theta))
                let y = s * 0.55 + r * CGFloat(sin(theta))
                ctx.setFillColor(cgColor(1, 1, 1, alpha: 0.7))
                ctx.addEllipse(in: CGRect(
                    x: x - sparkle * 0.5,
                    y: y - sparkle * 0.5,
                    width: sparkle, height: sparkle
                ))
                ctx.fillPath()
            }
        }

        // Subtle top-edge highlight to suggest the squircle "glass".
        let highlight = [
            cgColor(1, 1, 1, alpha: 0.10),
            cgColor(1, 1, 1, alpha: 0.0)
        ] as CFArray
        if let h = CGGradient(colorsSpace: cs, colors: highlight, locations: [0, 1]) {
            ctx.drawLinearGradient(
                h,
                start: CGPoint(x: 0, y: s),
                end: CGPoint(x: 0, y: s * 0.7),
                options: []
            )
        }

        return ctx.makeImage()
    }

    private static func cgColor(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat,
                                alpha: CGFloat = 1) -> CGColor {
        CGColor(red: r, green: g, blue: b, alpha: alpha)
    }

    private static func savePNG(_ image: CGImage, to url: URL) -> Bool {
        try? FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard let dest = CGImageDestinationCreateWithURL(
            url as CFURL,
            "public.png" as CFString,
            1, nil
        ) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}

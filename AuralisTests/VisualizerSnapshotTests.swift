import AppKit
import Metal
import XCTest
@testable import Auralis

@MainActor
final class VisualizerSnapshotTests: XCTestCase {

    func testAuroraRenders() throws { try snapshot(.aurora) }
    func testBloomRenders() throws { try snapshot(.bloom) }
    func testLatticeRenders() throws { try snapshot(.lattice) }
    func testFilamentRenders() throws { try snapshot(.filament) }
    func testHaloRenders() throws { try snapshot(.halo) }

    private func snapshot(_ mode: VisualizerID,
                          file: StaticString = #file,
                          line: UInt = #line) throws {
        let renderer = try XCTUnwrap(OffscreenRenderer(), "Metal device unavailable")
        let visualizer = try mode.build(device: renderer.device, format: renderer.format)
        let frame = TestFixtures.sampleFrame(renderer: renderer)
        let image = try XCTUnwrap(
            renderer.render(mode: visualizer, frame: frame, size: SIMD2(640, 360)),
            "\(mode.rawValue) render returned nil",
            file: file, line: line
        )

        // Attach the rendered image so failures can be inspected in
        // Xcode's Test report navigator.
        let nsImage = NSImage(cgImage: image,
                              size: NSSize(width: 640, height: 360))
        let attachment = XCTAttachment(image: nsImage)
        attachment.name = "\(mode.rawValue).png"
        attachment.lifetime = .keepAlways
        add(attachment)

        // Minimum-variance guard so a stub black/flat frame would fail.
        let variance = TestFixtures.pixelVariance(image)
        XCTAssertGreaterThan(variance, 0.0008,
                             "\(mode.rawValue) output is too flat (variance \(variance))",
                             file: file, line: line)
    }
}

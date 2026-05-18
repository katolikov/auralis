import Foundation
import XCTest
@testable import Auralis

final class AudioPipelineTests: XCTestCase {

    func testFFTFindsSinusoidPeak() {
        let n = 1024
        let sampleRate: Float = 48_000
        let frequency: Float = 1_000

        let fft = FFTAnalyzer(windowSize: n)
        var samples = [Float](repeating: 0, count: n)
        for i in 0..<n {
            samples[i] = sinf(Float(i) * 2 * .pi * frequency / sampleRate)
        }

        let mags = samples.withUnsafeBufferPointer { p in
            fft.analyze(window: p.baseAddress!)
        }
        XCTAssertEqual(mags.count, n / 2)

        let peakBin = mags.enumerated().max(by: { $0.element < $1.element })!.offset
        let binWidth = sampleRate / Float(n)
        let expectedBin = Int((frequency / binWidth).rounded())
        XCTAssertEqual(peakBin, expectedBin, accuracy: 2,
                       "FFT peak \(peakBin) doesn't match expected \(expectedBin)")
    }

    func testLogBinnerProducesExpectedCount() {
        let binner = LogBinner(binCount: 32, fftSize: 2048, sampleRate: 48_000)
        let mags = [Float](repeating: 0.1, count: 1024)
        let out = mags.withUnsafeBufferPointer { p in
            binner.bin(magnitudes: p.baseAddress!, count: 1024)
        }
        XCTAssertEqual(out.count, 32)
        for v in out {
            XCTAssertEqual(v, 0.1, accuracy: 0.05)
        }
    }

    func testBandComputerSeparatesEnergyByBand() {
        let bands = BandComputer(sampleRate: 48_000, fftSize: 2048)
        var mags = [Float](repeating: 0, count: 1024)
        // Inject energy roughly at 100 Hz (low), 1 kHz (mid), 8 kHz (high).
        let binFor: (Float) -> Int = { Int($0 / (48_000.0 / 2048)) }
        mags[binFor(100)] = 1.0
        mags[binFor(1_000)] = 1.0
        mags[binFor(8_000)] = 1.0

        let result = mags.withUnsafeBufferPointer { p in
            bands.compute(magnitudes: p.baseAddress!, count: mags.count)
        }
        XCTAssertGreaterThan(result.low, 0)
        XCTAssertGreaterThan(result.mid, 0)
        XCTAssertGreaterThan(result.high, 0)

        let loudness = bands.aWeightedLoudness(low: result.low,
                                                mid: result.mid,
                                                high: result.high)
        XCTAssertGreaterThan(loudness, 0)
    }

    func testOnsetDetectorFiresOnEnergySpike() {
        let detector = OnsetDetector(historySize: 20, minInterval: 0.05)
        let bins = 32

        // Feed baseline frames so the median/MAD threshold stabilizes.
        let baseline = [Float](repeating: 0.05, count: bins)
        for k in 0..<25 {
            _ = detector.process(magnitudes: baseline,
                                  at: TimeInterval(k) * 0.02)
        }

        // Now hit it with a clear spike.
        let spike = [Float](repeating: 0.8, count: bins)
        let result = detector.process(magnitudes: spike,
                                       at: TimeInterval(25) * 0.02)
        XCTAssertTrue(result.fired, "Onset detector failed to fire on spike")
        XCTAssertGreaterThan(result.envelope, 0.5)
    }

    func testPaletteExtractorReturnsColors() throws {
        // Build a 64x64 image with three solid quadrants.
        let size = 64
        let bytesPerRow = size * 4
        var buf = [UInt8](repeating: 0, count: bytesPerRow * size)
        for y in 0..<size {
            for x in 0..<size {
                let i = (y * size + x) * 4
                if x < size / 2 && y < size / 2 {
                    buf[i] = 220; buf[i+1] = 60; buf[i+2] = 40
                } else if x >= size / 2 && y < size / 2 {
                    buf[i] = 60; buf[i+1] = 220; buf[i+2] = 60
                } else if x < size / 2 && y >= size / 2 {
                    buf[i] = 60; buf[i+1] = 80; buf[i+2] = 220
                } else {
                    buf[i] = 230; buf[i+1] = 230; buf[i+2] = 230
                }
                buf[i+3] = 255
            }
        }
        let ctx = try XCTUnwrap(buf.withUnsafeMutableBufferPointer { ptr in
            CGContext(
                data: ptr.baseAddress,
                width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                space: CGColorSpace(name: CGColorSpace.sRGB)
                    ?? CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            )
        })
        let cg = try XCTUnwrap(ctx.makeImage())
        let palette = PaletteExtractor(k: 4).extract(from: cg)
        XCTAssertEqual(palette.count, 4)
        for color in palette {
            let mag = color.x + color.y + color.z
            XCTAssertGreaterThan(mag, 0.05,
                                  "Palette contains an unexpectedly dark cluster center")
        }
    }
}

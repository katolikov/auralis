import Accelerate
import Foundation

/// Real-input FFT with a precomputed Hann window using the legacy
/// `vDSP_fft_zrip` API (battle-tested, no setup re-allocation).
/// Stateless across calls; the caller owns the time-domain window.
final class FFTAnalyzer {
    let windowSize: Int
    let halfN: Int

    private let log2n: vDSP_Length
    private let setup: FFTSetup
    private var hannWindow: [Float]
    private var workReal: [Float]
    private var workImag: [Float]
    private var windowed: [Float]
    private let normalization: Float

    init(windowSize: Int = 2048) {
        precondition(windowSize > 0 && windowSize.nonzeroBitCount == 1,
                     "windowSize must be a positive power of two")
        self.windowSize = windowSize
        self.halfN = windowSize / 2
        self.log2n = vDSP_Length(log2f(Float(windowSize)).rounded())

        guard let setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2)) else {
            fatalError("vDSP_create_fftsetup failed")
        }
        self.setup = setup

        self.hannWindow = [Float](repeating: 0, count: windowSize)
        vDSP_hann_window(&hannWindow, vDSP_Length(windowSize), Int32(vDSP_HANN_NORM))

        self.workReal = [Float](repeating: 0, count: halfN)
        self.workImag = [Float](repeating: 0, count: halfN)
        self.windowed = [Float](repeating: 0, count: windowSize)

        // vDSP's packed real FFT produces values scaled by 2; divide by N
        // for unit DFT amplitudes and by another 2 to account for that scale.
        self.normalization = 1.0 / Float(windowSize)
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    /// Performs FFT on a `windowSize` Float32 buffer and returns
    /// `halfN` magnitudes (linear). DC is bin 0; Nyquist is dropped.
    func analyze(window: UnsafePointer<Float>) -> [Float] {
        // Apply Hann window.
        vDSP_vmul(window, 1, hannWindow, 1, &windowed, 1, vDSP_Length(windowSize))

        // Repack real signal into split-complex (even → real, odd → imag).
        windowed.withUnsafeBufferPointer { wp in
            wp.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: halfN) { cp in
                workReal.withUnsafeMutableBufferPointer { rp in
                    workImag.withUnsafeMutableBufferPointer { ip in
                        var split = DSPSplitComplex(realp: rp.baseAddress!,
                                                    imagp: ip.baseAddress!)
                        vDSP_ctoz(cp, 2, &split, 1, vDSP_Length(halfN))
                    }
                }
            }
        }

        // In-place forward FFT on split-complex storage.
        workReal.withUnsafeMutableBufferPointer { rp in
            workImag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!,
                                            imagp: ip.baseAddress!)
                vDSP_fft_zrip(setup, &split, 1, log2n,
                              FFTDirection(FFT_FORWARD))
            }
        }

        // Drop the Nyquist artifact packed into workImag[0] before magnitude.
        workImag[0] = 0

        var magnitudes = [Float](repeating: 0, count: halfN)
        workReal.withUnsafeMutableBufferPointer { rp in
            workImag.withUnsafeMutableBufferPointer { ip in
                var split = DSPSplitComplex(realp: rp.baseAddress!,
                                            imagp: ip.baseAddress!)
                vDSP_zvabs(&split, 1, &magnitudes, 1, vDSP_Length(halfN))
                var scale = normalization
                vDSP_vsmul(magnitudes, 1, &scale, &magnitudes, 1, vDSP_Length(halfN))
            }
        }
        return magnitudes
    }
}

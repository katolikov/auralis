import Accelerate
import AVFoundation
import CoreMedia

enum AudioMath {
    /// Computes the broadband RMS amplitude of a sample buffer.
    ///
    /// ScreenCaptureKit delivers non-interleaved Float32 audio. We average
    /// the per-channel mean-square via `vDSP_measqv`, then take the square
    /// root. Result is in linear amplitude (0.0–~1.0 for normalized PCM).
    static func rms(buffer: CMSampleBuffer) -> Float {
        guard let result = try? withAudioBufferList(buffer, { abl, frames in
            guard frames > 0, abl.count > 0 else { return Float(0) }
            var sum: Float = 0
            var counted = 0
            for ab in abl {
                guard let raw = ab.mData else { continue }
                let ptr = raw.assumingMemoryBound(to: Float.self)
                var meanSquare: Float = 0
                vDSP_measqv(ptr, 1, &meanSquare, vDSP_Length(frames))
                sum += meanSquare
                counted += 1
            }
            guard counted > 0 else { return Float(0) }
            return sqrtf(sum / Float(counted))
        }) else { return 0 }
        return result
    }

    private static func withAudioBufferList<R>(
        _ buffer: CMSampleBuffer,
        _ body: (UnsafeMutableAudioBufferListPointer, Int) throws -> R
    ) throws -> R {
        var sizeNeeded = 0
        let firstPass = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: &sizeNeeded,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        )
        guard firstPass == noErr || firstPass == kCMSampleBufferError_ArrayTooSmall else {
            throw NSError(domain: "AudioMath", code: Int(firstPass))
        }

        let raw = UnsafeMutableRawPointer.allocate(
            byteCount: sizeNeeded,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { raw.deallocate() }

        let abl = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
        var blockBuffer: CMBlockBuffer?
        let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            buffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: abl,
            bufferListSize: sizeNeeded,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard status == noErr else {
            throw NSError(domain: "AudioMath", code: Int(status))
        }

        let frames = Int(CMSampleBufferGetNumSamples(buffer))
        let pointer = UnsafeMutableAudioBufferListPointer(abl)
        return try body(pointer, frames)
    }
}

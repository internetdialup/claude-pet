import AVFoundation
import CoreGraphics
import Foundation

/// Encodes a sequence of frames as an H.264 MP4.
///
/// Social platforms take video, not GIF — an Instagram reel cannot be a GIF at
/// all, and at 1080×1920 a GIF would be both enormous and limited to 256
/// colours. AVFoundation ships with macOS, so this adds no package dependency:
/// `Package.swift` keeps an empty `dependencies` array, which is what makes the
/// "no network egress" claim checkable rather than promised.
enum VideoWriter {

    /// Writes `frames` at `fps` to an MP4 at `url`.
    ///
    /// Frames must all share the dimensions of the first. Returns false rather
    /// than throwing — every caller is a command-line renderer that wants a
    /// clean exit code.
    static func write(_ frames: [CGImage], to url: URL, fps: Int32) -> Bool {
        write(to: url, fps: fps, frameCount: frames.count) { frames[$0] }
    }

    /// The streaming spelling: frames are produced one at a time inside the
    /// append loop, so a long cut holds ONE frame in flight instead of the
    /// whole reel — at 1350 frames of 1920×1080 BGRA the accumulated array
    /// would be measured in gigabytes. `frame` returning nil aborts.
    static func write(to url: URL, fps: Int32, frameCount: Int,
                      frame: (Int) -> CGImage?) -> Bool {
        guard frameCount > 0, let first = frame(0) else { return false }
        let width = first.width, height = first.height

        // H.264 requires even dimensions. Every size here is a multiple of 2 by
        // construction, but a caller that picks an odd one should be told.
        guard width % 2 == 0, height % 2 == 0 else {
            FileHandle.standardError.write(Data("H.264 needs even dimensions, got \(width)×\(height)\n".utf8))
            return false
        }

        try? FileManager.default.removeItem(at: url)

        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mp4) else {
            FileHandle.standardError.write(Data("could not open \(url.path)\n".utf8))
            return false
        }

        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                // Flat colour with hard edges compresses very well; this is
                // generous so the pixel edges stay crisp rather than ringing.
                AVVideoAverageBitRateKey: 8_000_000,
                AVVideoMaxKeyFrameIntervalKey: fps,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            ],
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height,
            ])

        guard writer.canAdd(input) else { return false }
        writer.add(input)
        guard writer.startWriting() else {
            FileHandle.standardError.write(Data("writer refused to start: \(String(describing: writer.error))\n".utf8))
            return false
        }
        writer.startSession(atSourceTime: .zero)

        for index in 0..<frameCount {
            // Frame 0 was produced once for the dimension probe; re-request
            // is cheap against the alternative of holding it across the
            // writer setup.
            guard let image = frame(index) else { return false }
            // The input has a bounded queue; spin until it drains rather than
            // dropping frames, since this is offline and has no deadline.
            while !input.isReadyForMoreMediaData {
                Thread.sleep(forTimeInterval: 0.005)
            }
            guard let pool = adaptor.pixelBufferPool,
                  let buffer = pixelBuffer(from: image, pool: pool, width: width, height: height)
            else { return false }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(index), timescale: fps))
        }

        input.markAsFinished()
        let done = DispatchSemaphore(value: 0)
        writer.finishWriting { done.signal() }
        done.wait()

        guard writer.status == .completed else {
            FileHandle.standardError.write(Data("encode failed: \(String(describing: writer.error))\n".utf8))
            return false
        }
        return true
    }

    private static func pixelBuffer(from image: CGImage, pool: CVPixelBufferPool,
                                    width: Int, height: Int) -> CVPixelBuffer? {
        var out: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &out) == kCVReturnSuccess,
              let buffer = out else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: width, height: height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
                | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        // Nearest-neighbour: this is pixel art, and smoothing its edges is the
        // one thing that would make it stop looking like itself.
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return buffer
    }
}

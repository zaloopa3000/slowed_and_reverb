import Foundation
import ImageIO

/// Decoded GIF frames with their delays, downsampled for the chunky LCD look.
///
/// `CGImage` is immutable, so sharing decoded frames across threads is safe.
nonisolated struct AnimatedGIF: @unchecked Sendable {
    let frames: [CGImage]
    let delays: [TimeInterval]
    let duration: TimeInterval

    /// Decodes `data`, scaling frames so their longer side is at most `maxPixelSize`.
    /// Very long GIFs are capped at `maxFrames` to keep memory in check.
    init?(data: Data, maxPixelSize: Int, maxFrames: Int = 150) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 0 else { return nil }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        var frames: [CGImage] = []
        var delays: [TimeInterval] = []
        frames.reserveCapacity(count)
        delays.reserveCapacity(count)

        for index in 0..<count {
            guard let frame = CGImageSourceCreateThumbnailAtIndex(source, index, options as CFDictionary) else { continue }
            frames.append(frame)
            delays.append(Self.delay(of: source, at: index))
        }
        guard !frames.isEmpty else { return nil }

        self.frames = frames
        self.delays = delays
        self.duration = delays.reduce(0, +)
    }

    /// Frame to show `time` seconds into the (looping) animation.
    func frame(at time: TimeInterval) -> CGImage {
        guard frames.count > 1, duration > 0 else { return frames[0] }
        var remaining = time.truncatingRemainder(dividingBy: duration)
        if remaining < 0 { remaining += duration }
        for (index, delay) in delays.enumerated() {
            if remaining < delay { return frames[index] }
            remaining -= delay
        }
        return frames[frames.count - 1]
    }

    /// Per-frame delay; browsers treat tiny delays as 0.1 s, so do the same.
    private static func delay(of source: CGImageSource, at index: Int) -> TimeInterval {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else { return 0.1 }
        let unclamped = gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
        let clamped = gif[kCGImagePropertyGIFDelayTime] as? Double
        let delay = unclamped ?? clamped ?? 0.1
        return delay < 0.02 ? 0.1 : delay
    }
}

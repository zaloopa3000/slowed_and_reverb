import Foundation
import ImageIO

/// Decoded GIF frames with their delays, downsampled to keep memory in check.
///
/// `CGImage` is immutable, so sharing decoded frames across threads is safe.
nonisolated struct AnimatedGIF: @unchecked Sendable {
    let frames: [CGImage]
    let delays: [TimeInterval]
    let duration: TimeInterval

    /// Decodes `data`, scaling frames so their longer side is at most `maxPixelSize` —
    /// and smaller if needed so all decoded frames fit in `memoryBudget` bytes.
    /// Short GIFs keep near-source sharpness; long ones trade resolution for memory.
    init?(data: Data, maxPixelSize: Int, maxFrames: Int = 100, memoryBudget: Int = 48 << 20) {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let count = min(CGImageSourceGetCount(source), maxFrames)
        guard count > 0 else { return nil }

        // 4 bytes per pixel; assume square frames for a conservative per-frame side.
        let budgetSide = Int((Double(memoryBudget) / 4 / Double(count)).squareRoot())
        let pixelSize = max(min(maxPixelSize, budgetSide), 200)

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
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
        frames[frameIndex(at: time)]
    }

    /// Index of the frame to show `time` seconds into the (looping) animation.
    func frameIndex(at time: TimeInterval) -> Int {
        guard frames.count > 1, duration > 0 else { return 0 }
        var remaining = time.truncatingRemainder(dividingBy: duration)
        if remaining < 0 { remaining += duration }
        for (index, delay) in delays.enumerated() {
            if remaining < delay { return index }
            remaining -= delay
        }
        return frames.count - 1
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

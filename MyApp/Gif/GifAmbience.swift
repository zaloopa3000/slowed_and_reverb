import CoreGraphics

/// Tiny color field sampled from a GIF, used to tint the player body in the GIF's tones.
/// Downsampling to a handful of pixels averages the colors — a near-free heavy blur.
nonisolated enum GifAmbience {
    /// Frame to sample: the middle one, since first frames are often fades or blank.
    static func sourceFrame(of gif: AnimatedGIF) -> CGImage {
        gif.frames[gif.frames.count / 2]
    }

    /// `image` aspect-filled and centered into a `width` × `height` bitmap.
    static func thumbnail(of image: CGImage, width: Int = 12, height: Int = 20) -> CGImage? {
        guard width > 0, height > 0, image.width > 0, image.height > 0,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: width,
                  height: height,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: colorSpace,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let scale = max(CGFloat(width) / CGFloat(image.width), CGFloat(height) / CGFloat(image.height))
        let drawSize = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let origin = CGPoint(x: (CGFloat(width) - drawSize.width) / 2, y: (CGFloat(height) - drawSize.height) / 2)

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(origin: origin, size: drawSize))
        return context.makeImage()
    }
}

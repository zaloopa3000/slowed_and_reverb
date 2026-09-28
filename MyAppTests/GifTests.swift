import CoreGraphics
import Foundation
import Testing
@testable import MyApp

@Suite("GifEffect")
struct GifEffectTests {
    @Test func nextCyclesThroughAllEffects() {
        var effect = GifEffect.none
        var seen: [GifEffect] = []
        for _ in GifEffect.allCases {
            seen.append(effect)
            effect = effect.next
        }
        #expect(seen == GifEffect.allCases)
        #expect(effect == .none)
    }

    @Test func lastEffectWrapsToNone() {
        #expect(GifEffect.neon.next == .none)
    }

    @Test func titlesAreUniqueAndNonEmpty() {
        let titles = GifEffect.allCases.map(\.title)
        #expect(titles.allSatisfy { !$0.isEmpty })
        #expect(Set(titles).count == titles.count)
    }
}

@Suite("GifClock")
struct GifClockTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)

    @Test func firstAdvanceStartsAtZero() {
        #expect(GifClock().advance(to: start, rate: 1) == 0)
    }

    @Test func accumulatesAtRate() {
        let clock = GifClock()
        _ = clock.advance(to: start, rate: 1)
        let time = clock.advance(to: start.addingTimeInterval(0.05), rate: 2)
        #expect(abs(time - 0.1) < 1e-9)
    }

    @Test func clampsLargeGapsAndBackwardsTime() {
        let clock = GifClock()
        _ = clock.advance(to: start, rate: 1)
        // A 5 s gap (e.g. app in background) only advances by the 0.1 s cap.
        #expect(abs(clock.advance(to: start.addingTimeInterval(5), rate: 1) - 0.1) < 1e-9)
        // Going back in time never rewinds the clock.
        #expect(abs(clock.advance(to: start, rate: 1) - 0.1) < 1e-9)
    }
}

@Suite("AnimatedGIF")
struct AnimatedGIFTests {
    @Test func rejectsInvalidData() {
        #expect(AnimatedGIF(data: Data("not a gif".utf8), maxPixelSize: 100) == nil)
        #expect(AnimatedGIF(data: Data(), maxPixelSize: 100) == nil)
    }

    @Test func decodesFramesAndDelays() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.2, 0.3])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))

        #expect(gif.frames.count == 2)
        #expect(gif.delays.count == 2)
        #expect(abs(gif.delays[0] - 0.2) < 0.001)
        #expect(abs(gif.delays[1] - 0.3) < 0.001)
        #expect(abs(gif.duration - 0.5) < 0.001)
    }

    @Test func tinyDelaysBecomeATenthOfASecond() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.01, 0.01])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(gif.delays.allSatisfy { abs($0 - 0.1) < 0.001 })
    }

    @Test func respectsMaxFrames() throws {
        let data = try TestFixtures.makeGIFData(delays: Array(repeating: 0.1, count: 6))
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100, maxFrames: 4))
        #expect(gif.frames.count == 4)
    }

    @Test(arguments: [
        (0.0, 0),
        (0.19, 0),
        (0.2, 1),
        (0.49, 1),
        (0.5, 0),   // loops
        (0.75, 1),
        (-0.1, 1)   // negative time wraps from the end
    ])
    func frameIndexLoops(time: TimeInterval, expected: Int) throws {
        let data = try TestFixtures.makeGIFData(delays: [0.2, 0.3])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(gif.frameIndex(at: time) == expected)
    }

    @Test func singleFrameAlwaysShowsFirstFrame() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.5])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(gif.frameIndex(at: 0) == 0)
        #expect(gif.frameIndex(at: 123.4) == 0)
    }
}
@Suite("GifAmbience")
struct GifAmbienceTests {
    /// Solid-color RGBA image of the given size.
    private func solidImage(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat) throws -> CGImage {
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return try #require(context.makeImage())
    }

    /// RGBA bytes of `image`, redrawn into a known layout.
    private func pixels(of image: CGImage) throws -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try #require(CGContext(
                data: buffer.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8,
                bytesPerRow: image.width * 4, space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ))
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        }
        return bytes
    }

    @Test(arguments: [(200, 100), (100, 300), (12, 20), (1, 1)])
    func thumbnailHasRequestedSize(width: Int, height: Int) throws {
        let image = try solidImage(width: width, height: height, red: 0, green: 0, blue: 1)
        let thumbnail = try #require(GifAmbience.thumbnail(of: image))
        #expect(thumbnail.width == 12)
        #expect(thumbnail.height == 20)
    }

    @Test func thumbnailKeepsColorAndFillsEveryPixel() throws {
        let image = try solidImage(width: 300, height: 120, red: 1, green: 0, blue: 0)
        let thumbnail = try #require(GifAmbience.thumbnail(of: image))
        let bytes = try pixels(of: thumbnail)
        for index in stride(from: 0, to: bytes.count, by: 4) {
            #expect(bytes[index] > 240)       // red
            #expect(bytes[index + 1] < 15)    // green
            #expect(bytes[index + 2] < 15)    // blue
            #expect(bytes[index + 3] > 240)   // opaque: aspect-fill leaves no gaps
        }
    }

    @Test func rejectsEmptyTarget() throws {
        let image = try solidImage(width: 10, height: 10, red: 1, green: 1, blue: 1)
        #expect(GifAmbience.thumbnail(of: image, width: 0, height: 20) == nil)
    }

    @Test func sourceFrameIsTheMiddleFrame() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.1, 0.1, 0.1])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(GifAmbience.sourceFrame(of: gif) === gif.frames[1])
    }

    @Test func sourceFrameOfSingleFrameGIF() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.5])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(GifAmbience.sourceFrame(of: gif) === gif.frames[0])
    }
}


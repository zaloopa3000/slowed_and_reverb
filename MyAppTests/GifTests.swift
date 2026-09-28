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

    @Test func respectsMemoryBudgetButKeepsFirstFrame() throws {
        let data = try TestFixtures.makeGIFData(delays: Array(repeating: 0.1, count: 6))
        // An 8×8 RGBA frame takes at least 256 bytes, so a 1-byte budget still keeps one frame.
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100, maxBytes: 1))
        #expect(gif.frames.count == 1)
        #expect(gif.delays.count == 1)
    }

    @Test func frameMatchesFrameIndex() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.2, 0.3])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(gif.frame(at: 0.25) === gif.frames[1])
    }

    @Test func singleFrameAlwaysShowsFirstFrame() throws {
        let data = try TestFixtures.makeGIFData(delays: [0.5])
        let gif = try #require(AnimatedGIF(data: data, maxPixelSize: 100))
        #expect(gif.frameIndex(at: 0) == 0)
        #expect(gif.frameIndex(at: 123.4) == 0)
    }
}

@Suite("StaticNoise")
struct StaticNoiseTests {
    @Test func imageHasOnePixelPerCell() throws {
        let image = try #require(StaticNoise.noiseImage(columns: 12, rows: 5, seed: 1))
        #expect(image.width == 12)
        #expect(image.height == 5)
    }

    @Test func sameSeedGivesSamePattern() throws {
        let a = try #require(StaticNoise.noiseImage(columns: 8, rows: 8, seed: 42)?.dataProvider?.data as Data?)
        let b = try #require(StaticNoise.noiseImage(columns: 8, rows: 8, seed: 42)?.dataProvider?.data as Data?)
        let c = try #require(StaticNoise.noiseImage(columns: 8, rows: 8, seed: 43)?.dataProvider?.data as Data?)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func emptySizeGivesNoImage() {
        #expect(StaticNoise.noiseImage(columns: 0, rows: 4, seed: 1) == nil)
    }
}

import Foundation
import Testing
@testable import MyApp

@Suite("LevelMeter")
struct LevelMeterTests {
    private let start = Date(timeIntervalSinceReferenceDate: 1_000)
    private let chunks = [
        StereoLevel(left: -10, right: -12),
        StereoLevel(left: -5, right: -6),
        StereoLevel(left: 0, right: -1)
    ]

    @Test func emptyMeterReadsSilence() {
        let meter = LevelMeter()
        #expect(meter.level(at: .now) == .silence)
        #expect(StereoLevel.silence.left == LevelMeter.floor)
        #expect(StereoLevel.silence.right == LevelMeter.floor)
    }

    @Test func stepsThroughChunksOverTime() {
        let meter = LevelMeter()
        meter.push(chunks, chunkDuration: 0.02, at: start)

        #expect(meter.level(at: start) == chunks[0])
        #expect(meter.level(at: start.addingTimeInterval(0.025)) == chunks[1])
        #expect(meter.level(at: start.addingTimeInterval(0.045)) == chunks[2])
    }

    @Test func holdsLastChunkUntilStale() {
        let meter = LevelMeter()
        meter.push(chunks, chunkDuration: 0.02, at: start)

        #expect(meter.level(at: start.addingTimeInterval(0.3)) == chunks[2])
        #expect(meter.level(at: start.addingTimeInterval(0.6)) == .silence)
    }

    @Test func dateBeforeArrivalShowsFirstChunk() {
        let meter = LevelMeter()
        meter.push(chunks, chunkDuration: 0.02, at: start)
        #expect(meter.level(at: start.addingTimeInterval(-1)) == chunks[0])
    }

    @Test func emptyPushIsIgnored() {
        let meter = LevelMeter()
        meter.push(chunks, chunkDuration: 0.02, at: start)
        meter.push([], chunkDuration: 0.02, at: start.addingTimeInterval(0.1))
        #expect(meter.level(at: start) == chunks[0])
    }

    @Test func resetClearsLevels() {
        let meter = LevelMeter()
        meter.push(chunks, chunkDuration: 0.02, at: start)
        meter.reset()
        #expect(meter.level(at: start) == .silence)
    }
}

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

@Suite("LevelMeter.levels")
struct LevelMeterLevelsTests {
    @Test func silenceReadsFloor() {
        #expect(LevelMeter.decibels(rms: 0) == LevelMeter.floor)
        #expect(LevelMeter.decibels(rms: 1e-9) == LevelMeter.floor)
    }

    @Test func calibrationPutsLoudMixAtZero() {
        // -14 dBFS RMS reads as 0 on the meter.
        let rms = Float(pow(10, -14.0 / 20))
        #expect(abs(LevelMeter.decibels(rms: rms)) < 0.001)
    }

    @Test func splitsIntoChunksPerChannel() {
        // 5 frames, chunks of 2 → 3 chunks (the last one is short).
        let left: [Float] = [1, 1, 0, 0, 0.5]
        let right: [Float] = [0, 0, 1, 1, 0.5]
        let levels = left.withUnsafeBufferPointer { l in
            right.withUnsafeBufferPointer { r in
                LevelMeter.levels(left: l, right: r, chunkFrames: 2)
            }
        }
        #expect(levels.count == 3)
        #expect(abs(levels[0].left - LevelMeter.decibels(rms: 1)) < 0.001)
        #expect(levels[0].right == LevelMeter.floor)
        #expect(levels[1].left == LevelMeter.floor)
        #expect(abs(levels[1].right - LevelMeter.decibels(rms: 1)) < 0.001)
        #expect(abs(levels[2].left - levels[2].right) < 0.001)
    }

    @Test func emptyInputGivesNoChunks() {
        let empty: [Float] = []
        let levels = empty.withUnsafeBufferPointer { LevelMeter.levels(left: $0, right: $0, chunkFrames: 10) }
        #expect(levels.isEmpty)
    }
}

import Foundation
import Testing
@testable import MyApp

@Suite("VUScale")
struct VUScaleTests {
    @Test(arguments: [
        (Float(-60), CGFloat(0)),
        (-30, 0),
        (-20, 0.06),
        (-10, 0.3),
        (0, 0.69),
        (3, 0.88),
        (6, 1),
        (12, 1)
    ])
    func positionAtMarks(db: Float, expected: CGFloat) {
        #expect(abs(VUScale.position(for: db) - expected) < 0.0001)
    }

    @Test func interpolatesBetweenMarks() {
        // Halfway between -10 dB (0.3) and -6 dB (0.43).
        #expect(abs(VUScale.position(for: -8) - 0.365) < 0.0001)
    }

    @Test func positionIsMonotonic() {
        var previous = VUScale.position(for: -40)
        for step in stride(from: Float(-40), through: 10, by: 0.5) {
            let position = VUScale.position(for: step)
            #expect(position >= previous)
            #expect((0...1).contains(position))
            previous = position
        }
    }

    @Test func zeroPositionMatchesZeroMark() {
        #expect(VUScale.position(for: 0) == VUScale.zeroPosition)
    }
}

@Suite("MeterBallistics")
struct MeterBallisticsTests {
    private let start = Date(timeIntervalSinceReferenceDate: 0)
    private let loud = StereoLevel(left: 0, right: -6)

    @Test func firstFrameDoesNotMove() {
        let ballistics = MeterBallistics()
        let display = ballistics.advance(to: start, target: loud)
        #expect(display.left == LevelMeter.floor)
        #expect(display.right == LevelMeter.floor)
    }

    @Test func attackIsFast() {
        let ballistics = MeterBallistics()
        _ = ballistics.advance(to: start, target: loud)
        let display = ballistics.advance(to: start.addingTimeInterval(0.1), target: loud)

        // 0.1 s is > 3 attack time constants → within ~4% of the target.
        #expect(display.left > -2 && display.left <= 0)
        #expect(display.right > -8 && display.right <= -6)
        #expect(display.leftPeak == display.left)
        #expect(display.rightPeak == display.right)
    }

    @Test func releaseIsSlowerThanAttack() {
        let ballistics = MeterBallistics()
        _ = ballistics.advance(to: start, target: loud)
        let up = ballistics.advance(to: start.addingTimeInterval(0.1), target: loud)
        let down = ballistics.advance(to: start.addingTimeInterval(0.2), target: .silence)

        #expect(down.left < up.left)
        // Release covers far less than the full drop in 0.1 s.
        #expect(down.left > LevelMeter.floor + 20)
    }

    @Test func peakHoldsThenFalls() {
        let ballistics = MeterBallistics()
        _ = ballistics.advance(to: start, target: loud)
        let hit = ballistics.advance(to: start.addingTimeInterval(0.1), target: loud)

        // Within the 1 s hold the peak stays put.
        var date = start.addingTimeInterval(0.1)
        var display = hit
        for _ in 0..<5 {
            date.addTimeInterval(0.1)
            display = ballistics.advance(to: date, target: .silence)
        }
        #expect(display.leftPeak == hit.leftPeak)

        // After the hold it falls, but never below the live level.
        for _ in 0..<20 {
            date.addTimeInterval(0.1)
            display = ballistics.advance(to: date, target: .silence)
            #expect(display.leftPeak >= display.left)
        }
        #expect(display.leftPeak < hit.leftPeak)
    }

    @Test func largeGapsAreClamped() {
        let ballistics = MeterBallistics()
        _ = ballistics.advance(to: start, target: loud)
        let afterGap = ballistics.advance(to: start.addingTimeInterval(60), target: loud)
        let afterStep = MeterBallistics()
        _ = afterStep.advance(to: start, target: loud)
        let reference = afterStep.advance(to: start.addingTimeInterval(0.1), target: loud)
        #expect(afterGap.left == reference.left)
    }
}

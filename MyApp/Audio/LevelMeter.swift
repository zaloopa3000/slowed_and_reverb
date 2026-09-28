import Accelerate
import Foundation
import Observation

/// Left / right level in "VU dB" (0 dB ≈ a loud mix, see `LevelMeter.calibration`).
nonisolated struct StereoLevel: Sendable, Equatable {
    var left: Float
    var right: Float

    static let silence = StereoLevel(left: LevelMeter.floor, right: LevelMeter.floor)
}

/// Post-effects output levels for the L/R meter.
///
/// Audio taps deliver 100–400 ms buffers, which would make the meter jump ~10 times
/// a second. So each buffer is split into short chunks, and the view "plays" those
/// chunks back over time → smooth ~50 Hz motion.
///
/// Kept separate from `AudioEngine` so these frequent updates only invalidate the meter.
@Observable
final class LevelMeter {
    /// Floor of the meter scale; anything quieter reads as silence.
    nonisolated static let floor: Float = -40
    /// Added to the RMS level in dBFS so that 0 on the meter ≈ a loud, mastered mix (-14 dBFS RMS).
    nonisolated static let calibration: Float = 14
    /// Length of one meter chunk; the tap splits each buffer into chunks this long.
    nonisolated static let chunkLength: TimeInterval = 0.02

    private var chunks: [StereoLevel] = []
    private var chunkDuration: TimeInterval = 0.02
    private var arrival: Date = .distantPast

    func push(_ chunks: [StereoLevel], chunkDuration: TimeInterval, at date: Date = .now) {
        guard !chunks.isEmpty else { return }
        self.chunks = chunks
        self.chunkDuration = chunkDuration
        arrival = date
    }

    func reset() {
        chunks = []
    }

    /// Splits the samples into `chunkFrames`-long chunks and returns each chunk's
    /// L / R RMS level in meter dB (clamped to `floor`). Runs on the audio thread.
    nonisolated static func levels(
        left: UnsafeBufferPointer<Float>,
        right: UnsafeBufferPointer<Float>,
        chunkFrames: Int
    ) -> [StereoLevel] {
        let frames = min(left.count, right.count)
        guard frames > 0, chunkFrames > 0 else { return [] }
        var result: [StereoLevel] = []
        result.reserveCapacity(frames / chunkFrames + 1)
        var start = 0
        while start < frames {
            let end = min(start + chunkFrames, frames)
            result.append(StereoLevel(
                left: decibels(rms: vDSP.rootMeanSquare(UnsafeBufferPointer(rebasing: left[start..<end]))),
                right: decibels(rms: vDSP.rootMeanSquare(UnsafeBufferPointer(rebasing: right[start..<end])))
            ))
            start = end
        }
        return result
    }

    /// RMS amplitude (1 = full scale) → meter dB.
    nonisolated static func decibels(rms: Float) -> Float {
        guard rms > 0 else { return LevelMeter.floor }
        return max(20 * log10(rms) + LevelMeter.calibration, LevelMeter.floor)
    }

    /// Level to show at `date`, stepping through the latest buffer's chunks.
    func level(at date: Date) -> StereoLevel {
        guard let last = chunks.last else { return .silence }
        let elapsed = date.timeIntervalSince(arrival)
        // No fresh audio for a while (engine stopped) → silence.
        guard elapsed < 0.5 else { return .silence }
        let index = Int(max(elapsed, 0) / chunkDuration)
        return index < chunks.count ? chunks[index] : last
    }
}

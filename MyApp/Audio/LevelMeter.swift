import Foundation
import Observation

/// Left / right level in "VU dB" (0 dB ≈ a loud mix, see `AudioEngine.meterCalibration`).
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

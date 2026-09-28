import SwiftUI

/// Stereo L / R level meter with a dB scale between the channels. Few, chunky segments —
/// always wider than they are tall — glowing blue → violet, pink above 0 dB,
/// plus a peak segment that lingers and then falls.
struct StereoMeterView: View {
    let meter: LevelMeter
    let isPlaying: Bool

    @State private var ballistics = MeterBallistics()
    /// Keeps animating briefly after stopping so the bars can fall back smoothly.
    @State private var isSettling = false

    @Environment(\.pixelUnit) private var unit
    @Environment(\.displayScale) private var displayScale

    /// Segments per channel.
    static let segments = 10

    var body: some View {
        let labelPixel = PixelText.snapped(unit * 0.5, scale: displayScale)
        let legendWidth = CGFloat(PixelFont.width(of: "dB")) * labelPixel
        let panel = RoundedRectangle(cornerRadius: 6, style: .continuous)

        TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !(isPlaying || isSettling))) { context in
            let display = ballistics.advance(to: context.date, target: meter.level(at: context.date))

            VStack(spacing: unit * 2) {
                row("L", legendWidth: legendWidth, pixel: labelPixel) {
                    MeterBar(level: display.left, peak: display.leftPeak, segments: Self.segments)
                }
                row("dB", legendWidth: legendWidth, pixel: labelPixel) {
                    ScaleRow(pixel: labelPixel)
                }
                .fixedSize(horizontal: false, vertical: true)
                row("R", legendWidth: legendWidth, pixel: labelPixel) {
                    MeterBar(level: display.right, peak: display.rightPeak, segments: Self.segments)
                }
            }
        }
        .padding(.horizontal, unit * 3)
        .padding(.vertical, unit * 3)
        .frame(maxHeight: .infinity)
        .background {
            panel.fill(
                LinearGradient(
                    colors: [Color(red: 0.08, green: 0.08, blue: 0.12), Color(red: 0.03, green: 0.03, blue: 0.05)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .clipShape(panel)
        // Recessed into the body: dark top rim, light lower lip.
        .overlay {
            panel.strokeBorder(
                LinearGradient(colors: [.black.opacity(0.8), .white.opacity(0.22)], startPoint: .top, endPoint: .bottom),
                lineWidth: 1.2
            )
        }
        .onChange(of: isPlaying) { _, playing in
            guard !playing else { return }
            isSettling = true
            Task {
                // Long enough for a held peak (1 s hold + ~3 s fall) to reach the floor.
                try? await Task.sleep(for: .seconds(4))
                isSettling = false
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Level meter")
    }

    private func row<Content: View>(
        _ legend: String,
        legendWidth: CGFloat,
        pixel: CGFloat,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: unit * 2) {
            PixelText(legend, pixel: pixel)
                .foregroundStyle(MeterPalette.label)
                .frame(width: legendWidth, alignment: .leading)
            content()
        }
    }
}

// MARK: - Scale

/// Non-linear meter scale: most of the travel is spent between -10 and 0 dB, like a real VU.
nonisolated enum VUScale {
    struct Mark {
        let db: Float
        let position: CGFloat
        let label: String?
    }

    static let marks: [Mark] = [
        Mark(db: -30, position: 0, label: nil),
        Mark(db: -20, position: 0.06, label: "-20"),
        Mark(db: -10, position: 0.3, label: "-10"),
        Mark(db: -6, position: 0.43, label: "-6"),
        Mark(db: -3, position: 0.55, label: "-3"),
        Mark(db: 0, position: 0.69, label: "0"),
        Mark(db: 3, position: 0.88, label: "+3"),
        Mark(db: 6, position: 1, label: "+6")
    ]

    /// Position of the 0 dB mark: segments beyond it are "in the red".
    static let zeroPosition: CGFloat = 0.69

    /// 0…1 position along the bar for a level, interpolated between marks.
    static func position(for db: Float) -> CGFloat {
        guard let first = marks.first, let last = marks.last else { return 0 }
        if db <= first.db { return 0 }
        if db >= last.db { return 1 }
        for (lower, upper) in zip(marks, marks.dropFirst()) where db <= upper.db {
            let t = CGFloat((db - lower.db) / (upper.db - lower.db))
            return lower.position + (upper.position - lower.position) * t
        }
        return 1
    }
}

private enum MeterPalette {
    static let blue = Color(red: 0.45, green: 0.78, blue: 1.0)
    static let violet = Color(red: 0.67, green: 0.55, blue: 1.0)
    static let pink = Color(red: 0.96, green: 0.5, blue: 0.9)
    static let off = Color(red: 0.14, green: 0.15, blue: 0.22)
    static let peak = Color(red: 0.93, green: 0.9, blue: 1.0)
    static let label = Color(red: 0.72, green: 0.62, blue: 1.0)

    /// Lit segment color: blue → violet up to 0 dB, violet → pink above it.
    static func lit(at position: CGFloat) -> Color {
        if position <= VUScale.zeroPosition {
            return blue.mix(with: violet, by: Double(position / VUScale.zeroPosition))
        }
        let t = (position - VUScale.zeroPosition) / (1 - VUScale.zeroPosition)
        return violet.mix(with: pink, by: Double(t))
    }
}

// MARK: - Bars

/// One channel: a few chunky segments, lit ones glowing. Segments are always wider than tall;
/// if the row is taller than that, they're centered vertically.
private struct MeterBar: View {
    let level: Float
    let peak: Float
    let segments: Int

    @Environment(\.displayScale) private var displayScale

    var body: some View {
        Canvas { context, size in
            func snap(_ value: CGFloat) -> CGFloat { (value * displayScale).rounded() / displayScale }

            let step = size.width / CGFloat(segments)
            let segmentWidth = snap(step * 0.84)
            let segmentHeight = snap(min(size.height, segmentWidth * 0.7))
            let y = snap((size.height - segmentHeight) / 2)

            let lit = Int((VUScale.position(for: level) * CGFloat(segments)).rounded())
            let peakIndex = peak > LevelMeter.floor + 1
                ? min(Int((VUScale.position(for: peak) * CGFloat(segments)).rounded()) - 1, segments - 1)
                : -1

            func rect(_ index: Int) -> CGRect {
                CGRect(x: snap(CGFloat(index) * step), y: y, width: segmentWidth, height: segmentHeight)
            }

            for index in 0..<segments where index >= lit && index != peakIndex {
                context.fill(Path(rect(index)), with: .color(MeterPalette.off))
            }

            context.drawLayer { glow in
                glow.addFilter(.shadow(color: MeterPalette.violet.opacity(0.85), radius: 3))
                for index in 0..<min(lit, segments) {
                    let position = (CGFloat(index) + 0.5) / CGFloat(segments)
                    glow.fill(Path(rect(index)), with: .color(MeterPalette.lit(at: position)))
                }
                if peakIndex >= lit {
                    glow.fill(Path(rect(peakIndex)), with: .color(MeterPalette.peak))
                }
            }
        }
    }
}

/// dB labels under the marks; labels that would collide on narrow screens are skipped.
private struct ScaleRow: View {
    let pixel: CGFloat

    var body: some View {
        let height = CGFloat(PixelFont.glyphHeight) * pixel
        GeometryReader { geo in
            let placed = placements(width: geo.size.width)
            ZStack(alignment: .topLeading) {
                ForEach(placed, id: \.label) { item in
                    PixelText(item.label, pixel: pixel)
                        .foregroundStyle(MeterPalette.label.opacity(item.isZero ? 1 : 0.8))
                        .offset(x: item.x)
                }
            }
        }
        .frame(height: height)
    }

    private struct Placement {
        let label: String
        let x: CGFloat
        let isZero: Bool
    }

    private func placements(width: CGFloat) -> [Placement] {
        var result: [Placement] = []
        var lastRight: CGFloat = -.infinity
        for mark in VUScale.marks {
            guard let label = mark.label else { continue }
            let labelWidth = CGFloat(PixelFont.width(of: label)) * pixel
            // Center on the mark, but keep the label inside the bar.
            let x = min(max(mark.position * width - labelWidth / 2, 0), width - labelWidth)
            guard x >= lastRight + pixel * 3 else { continue }
            result.append(Placement(label: label, x: x, isZero: mark.db == 0))
            lastRight = x + labelWidth
        }
        return result
    }
}

// MARK: - Ballistics

/// Meter needle-style motion: fast attack, slow release, and a peak marker that
/// holds for a second before falling. A plain class, advanced from the render pass.
final class MeterBallistics {
    struct Display {
        let left: Float
        let right: Float
        let leftPeak: Float
        let rightPeak: Float
    }

    private var lastDate: Date?
    private var left = LevelMeter.floor
    private var right = LevelMeter.floor
    private var leftPeak = LevelMeter.floor
    private var rightPeak = LevelMeter.floor
    private var leftPeakDate = Date.distantPast
    private var rightPeakDate = Date.distantPast

    private let attack: Double = 0.03
    private let release: Double = 0.3
    private let peakHold: TimeInterval = 1
    /// How fast a released peak falls, in dB per second.
    private let peakFall: Float = 14

    func advance(to date: Date, target: StereoLevel) -> Display {
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1)
        lastDate = date

        left = smooth(left, toward: target.left, dt: dt)
        right = smooth(right, toward: target.right, dt: dt)
        updatePeak(&leftPeak, since: &leftPeakDate, level: left, date: date, dt: dt)
        updatePeak(&rightPeak, since: &rightPeakDate, level: right, date: date, dt: dt)

        return Display(left: left, right: right, leftPeak: leftPeak, rightPeak: rightPeak)
    }

    private func smooth(_ value: Float, toward target: Float, dt: Double) -> Float {
        let tau = target > value ? attack : release
        return value + (target - value) * Float(1 - exp(-dt / tau))
    }

    private func updatePeak(_ peak: inout Float, since peakDate: inout Date, level: Float, date: Date, dt: Double) {
        if level >= peak {
            peak = level
            peakDate = date
        } else if date.timeIntervalSince(peakDate) > peakHold {
            peak = max(peak - peakFall * Float(dt), level)
        }
    }
}

#Preview {
    let meter = LevelMeter()
    meter.push([StereoLevel(left: -3, right: -8)], chunkDuration: 60)
    return StereoMeterView(meter: meter, isPlaying: true)
        .frame(height: 80)
        .playerPreview()
}

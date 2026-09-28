import SwiftUI

/// A retro fader that snaps to fixed steps, draws a tick scale,
/// and gives a haptic click on every step (stronger on major ticks / detents).
struct SteppedSlider: View {
    let title: String
    @Binding var value: Float
    let range: ClosedRange<Float>
    let step: Float
    /// Every `majorEvery`-th tick is long and labeled.
    let majorEvery: Int
    /// Extra step indices that get a stronger "detent" click (e.g. 1.00x).
    var detents: Set<Int> = []
    let valueText: (Float) -> String
    let tickLabel: (Float) -> String

    @State private var isDragging = false
    @Environment(\.pixelUnit) private var unit
    @Environment(\.displayScale) private var displayScale

    private let knobSize = CGSize(width: 20, height: 28)
    private let trackHeight: CGFloat = 48
    private var grooveY: CGFloat { knobSize.height / 2 + 1 }
    /// Pixel size for the tiny scale labels (1 pt on a typical iPhone).
    private var labelPixel: CGFloat { PixelText.snapped(unit * 0.5, scale: displayScale) }

    private var stepCount: Int {
        Int(((range.upperBound - range.lowerBound) / step).rounded())
    }

    /// Current value expressed as a step index, 0…stepCount.
    private var index: Int {
        let raw = Int(((value - range.lowerBound) / step).rounded())
        return min(max(raw, 0), stepCount)
    }

    private func value(at index: Int) -> Float {
        range.lowerBound + Float(index) * step
    }

    private func isStrongStep(_ index: Int) -> Bool {
        index % majorEvery == 0 || detents.contains(index)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: unit * 3) {
                PixelText(title, pixel: unit * 0.8)
                    .foregroundStyle(RetroTheme.text.opacity(0.8))
                    .pixelShadow(.black.opacity(0.5), offset: 1)
                readout
            }
            .frame(width: 66, alignment: .leading)

            track
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(valueText(value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = value(at: min(index + 1, stepCount))
            case .decrement: value = value(at: max(index - 1, 0))
            @unknown default: break
            }
        }
    }

    // MARK: Readout

    /// Small dot-matrix readout ("0.85X", "40%").
    private var readout: some View {
        let pixel = min(unit, 66 / CGFloat(PixelFont.width(of: valueText(range.upperBound)) + 8))
        return PixelText(valueText(value), pixel: pixel)
            .foregroundStyle(RetroTheme.lcdText)
            .lcdGlow(radius: 2)
            .padding(.vertical, pixel * 2.5)
            .frame(maxWidth: .infinity)
            .background {
                PixelNotchedRect(step: pixel, steps: 1)
                    .fill(RetroTheme.lcdGlass.mix(with: .black, by: 0.35).opacity(0.5))
                    .overlay {
                        PixelNotchedRect(step: pixel, steps: 1)
                            .stroke(Color.black.opacity(0.35), lineWidth: pixel)
                    }
            }
    }

    // MARK: Track

    private var track: some View {
        GeometryReader { geo in
            let usable = max(geo.size.width - knobSize.width, 1)
            let knobX = knobSize.width / 2 + usable * CGFloat(index) / CGFloat(stepCount)

            ZStack(alignment: .topLeading) {
                tickScale(usable: usable)

                // Square-cut groove the fader runs in, with a light lower lip.
                Rectangle()
                    .fill(Color.black.opacity(0.8))
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(Color.white.opacity(0.2)).frame(height: 1).offset(y: 1)
                    }
                    .frame(width: geo.size.width, height: 6)
                    .offset(y: grooveY - 3)

                // Lit portion of the groove: a glowing pixel line.
                Rectangle()
                    .fill(RetroTheme.accentRed)
                    .shadow(color: RetroTheme.accentRed.opacity(0.8), radius: 3)
                    .frame(width: max(knobX - 2, 0), height: 2)
                    .offset(x: 1, y: grooveY - 1)

                FaderKnob(isDragging: isDragging)
                    .frame(width: knobSize.width, height: knobSize.height)
                    .position(x: knobX, y: grooveY)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        isDragging = true
                        let fraction = (gesture.location.x - knobSize.width / 2) / usable
                        let newIndex = min(max(Int((fraction * CGFloat(stepCount)).rounded()), 0), stepCount)
                        if newIndex != index {
                            value = value(at: newIndex)
                        }
                    }
                    .onEnded { _ in
                        isDragging = false
                    }
            )
            // Knob snaps into each detent with a tiny spring.
            .animation(.spring(response: 0.16, dampingFraction: 0.72), value: index)
            .animation(.spring(response: 0.2, dampingFraction: 0.7), value: isDragging)
        }
        .frame(height: trackHeight)
        .sensoryFeedback(trigger: index) { _, newIndex in
            isStrongStep(newIndex)
                ? .impact(weight: .medium, intensity: 1)
                : .selection
        }
    }

    private func tickScale(usable: CGFloat) -> some View {
        let currentIndex = index
        let tickTop = grooveY + 8
        let majorLength: CGFloat = 8
        let tickWidth = PixelText.snapped(1, scale: displayScale)

        return ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                for i in 0...stepCount {
                    // Snap to device pixels so every tick is equally crisp.
                    let rawX = knobSize.width / 2 + usable * CGFloat(i) / CGFloat(stepCount)
                    let x = (rawX * displayScale).rounded() / displayScale - tickWidth / 2
                    let isMajor = i % majorEvery == 0
                    let isDetent = detents.contains(i)
                    let length: CGFloat = isMajor ? majorLength : (isDetent ? 6 : 4)
                    // Ticks at or below the knob are brighter, like a lit scale.
                    let opacity = i <= currentIndex ? 0.95 : 0.4
                    context.fill(
                        Path(CGRect(x: x, y: tickTop, width: isMajor ? tickWidth * 2 : tickWidth, height: length)),
                        with: .color(RetroTheme.text.opacity(opacity))
                    )
                }
            }

            ForEach(Array(stride(from: 0, through: stepCount, by: majorEvery)), id: \.self) { i in
                PixelText(tickLabel(value(at: i)), pixel: labelPixel)
                    .foregroundStyle(RetroTheme.text.opacity(i == currentIndex ? 1 : 0.6))
                    .position(
                        x: knobSize.width / 2 + usable * CGFloat(i) / CGFloat(stepCount),
                        y: tickTop + majorLength + 4 + labelPixel * CGFloat(PixelFont.glyphHeight) / 2
                    )
            }
        }
    }
}

/// Metal fader cap with grip ridges and a red index line.
private struct FaderKnob: View {
    let isDragging: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        shape
            .fill(
                LinearGradient(
                    colors: [Color(white: 0.9), Color(white: 0.62), Color(white: 0.5), Color(white: 0.72)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay {
                VStack(spacing: 3) {
                    ForEach(0..<4, id: \.self) { _ in
                        Rectangle()
                            .fill(Color.black.opacity(0.3))
                            .frame(height: 1)
                            .overlay(alignment: .bottom) {
                                Rectangle().fill(Color.white.opacity(0.4)).frame(height: 0.5).offset(y: 1)
                            }
                    }
                }
                .padding(.horizontal, 3)
            }
            .overlay {
                Rectangle()
                    .fill(RetroTheme.accentRed)
                    .frame(width: 2)
                    .padding(.vertical, 3)
            }
            .overlay {
                shape.strokeBorder(Color.black.opacity(0.55), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.55), radius: isDragging ? 6 : 2.5, y: isDragging ? 5 : 2)
            .scaleEffect(isDragging ? 1.1 : 1)
    }
}

#Preview {
    @Previewable @State var speed: Float = 1.0
    @Previewable @State var reverb: Float = 30
    VStack(spacing: 20) {
        SteppedSlider(
            title: "Speed",
            value: $speed,
            range: 0.5...1.5,
            step: 0.05,
            majorEvery: 5,
            detents: [10],
            valueText: { String(format: "%.2fx", $0) },
            tickLabel: { String(format: "%g", $0) }
        )
        SteppedSlider(
            title: "Reverb",
            value: $reverb,
            range: 0...100,
            step: 5,
            majorEvery: 5,
            valueText: { "\(Int($0.rounded()))%" },
            tickLabel: { String(format: "%g", $0) }
        )
    }
    .padding(24)
    .background(RetroTheme.body)
}

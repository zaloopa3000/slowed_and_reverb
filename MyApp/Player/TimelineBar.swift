import SwiftUI

/// Segmented (block-by-block) progress bar with drag-to-seek and pixel time readouts.
struct TimelineBar: View {
    let currentTime: TimeInterval
    let duration: TimeInterval
    let onSeek: (TimeInterval) -> Void

    /// Fraction under the finger while scrubbing; nil when idle.
    @State private var scrubFraction: Double?
    @Environment(\.pixelUnit) private var unit
    @Environment(\.displayScale) private var displayScale

    private var fraction: Double {
        if let scrubFraction { return scrubFraction }
        return duration > 0 ? min(max(currentTime / duration, 0), 1) : 0
    }

    private var shownTime: TimeInterval { fraction * duration }

    var body: some View {
        let pixel = PixelText.snapped(unit * 0.8, scale: displayScale)
        // Wide enough for "-00:00" so the bar doesn't jump as digits change.
        let labelWidth = CGFloat(PixelFont.width(of: "-00:00")) * pixel

        HStack(spacing: unit * 4) {
            PixelText(Self.format(shownTime), pixel: pixel)
                .frame(width: labelWidth, alignment: .leading)

            GeometryReader { geo in
                segments(width: geo.size.width, height: geo.size.height)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                scrubFraction = min(max(gesture.location.x / max(geo.size.width, 1), 0), 1)
                            }
                            .onEnded { _ in
                                if let scrubFraction {
                                    onSeek(scrubFraction * duration)
                                }
                                scrubFraction = nil
                            }
                    )
            }
            .frame(height: unit * 6)

            PixelText("-" + Self.format(max(duration - shownTime, 0)), pixel: pixel)
                .frame(width: labelWidth, alignment: .trailing)
        }
        .foregroundStyle(RetroTheme.text.opacity(0.85))
        .disabled(duration <= 0)
        .sensoryFeedback(.selection, trigger: scrubFraction == nil)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Position")
        .accessibilityValue(Self.format(shownTime))
    }

    /// Row of square blocks; lit blocks glow, the head block is red.
    private func segments(width: CGFloat, height: CGFloat) -> some View {
        let block = PixelText.snapped(unit * 1.5, scale: displayScale)
        let gap = PixelText.snapped(unit * 0.75, scale: displayScale)
        let count = max(Int((width + gap) / (block + gap)), 1)
        let lit = Int((fraction * Double(count)).rounded(.down))
        let blockHeight = height * 0.6

        return Canvas { context, size in
            // Center the blocks in the available width.
            let used = CGFloat(count) * block + CGFloat(count - 1) * gap
            let startX = ((size.width - used) / 2 * displayScale).rounded() / displayScale
            let y = ((size.height - blockHeight) / 2 * displayScale).rounded() / displayScale
            for i in 0..<count {
                let rect = CGRect(x: startX + CGFloat(i) * (block + gap), y: y, width: block, height: blockHeight)
                let color: Color
                if i == lit, duration > 0 {
                    color = RetroTheme.accentRed
                } else if i < lit {
                    color = RetroTheme.lcdText
                } else {
                    color = Color.black.opacity(0.55)
                }
                context.fill(Path(rect), with: .color(color))
            }
        }
        .shadow(color: RetroTheme.lcdText.opacity(0.35), radius: 3)
    }

    private static func format(_ time: TimeInterval) -> String {
        Duration.seconds(time.rounded(.down)).formatted(.time(pattern: .minuteSecond))
    }
}

#Preview {
    VStack(spacing: 24) {
        TimelineBar(currentTime: 42, duration: 180, onSeek: { _ in })
        TimelineBar(currentTime: 0, duration: 0, onSeek: { _ in })
    }
    .playerPreview()
}

import SwiftUI

/// Dot-matrix strip with "♥ TITLE — ARTIST ♥", scrolling in pixel steps when it doesn't fit.
struct TrackInfoStrip: View {
    let text: String

    @Environment(\.pixelUnit) private var unit

    var body: some View {
        let pixel = unit
        HStack(spacing: pixel * 4) {
            PixelText("♥", pixel: pixel)
            DotMatrixMarquee(text: text, pixel: pixel)
            PixelText("♥", pixel: pixel)
        }
        .foregroundStyle(RetroTheme.lcdText)
        .lcdGlow()
        .padding(.horizontal, pixel * 6)
        .padding(.vertical, pixel * 4)
        .background {
            PixelNotchedRect(step: pixel, steps: 2)
                .fill(RetroTheme.lcdGlass.mix(with: .black, by: 0.35))
                .overlay {
                    // Unlit dot grid of the matrix display.
                    DotGrid(pitch: pixel)
                        .fill(Color.white.opacity(0.05))
                        .padding(pixel * 2)
                }
                .overlay {
                    PixelNotchedRect(step: pixel, steps: 2)
                        .stroke(Color.black.opacity(0.75), lineWidth: pixel)
                }
                // Light metal lip under the recess.
                .shadow(color: .white.opacity(0.15), radius: 0, y: 1)
        }
    }
}

/// Grid of pixel dots, one per matrix cell (lit text sits on top of it).
struct DotGrid: Shape {
    let pitch: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let dot = pitch * 0.6
        var y = rect.minY
        while y + dot <= rect.maxY {
            var x = rect.minX
            while x + dot <= rect.maxX {
                path.addRect(CGRect(x: x, y: y, width: dot, height: dot))
                x += pitch
            }
            y += pitch
        }
        return path
    }
}

/// Single-line pixel text that scrolls in a loop, one pixel per step, when it overflows.
private struct DotMatrixMarquee: View {
    let text: String
    let pixel: CGFloat

    @State private var boxWidth: CGFloat = 0
    @Environment(\.displayScale) private var displayScale

    private let pixelsPerSecond: Double = 14
    private let gapColumns = 12

    var body: some View {
        let snapped = PixelText.snapped(pixel, scale: displayScale)
        let textWidth = CGFloat(PixelFont.width(of: text)) * snapped
        let overflows = textWidth > boxWidth + 0.5
        let height = CGFloat(PixelFont.glyphHeight) * snapped

        // Text lives in an overlay so its width never affects layout.
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .overlay(alignment: overflows ? .leading : .center) {
                TimelineView(.periodic(from: .now, by: 1 / pixelsPerSecond)) { context in
                    let cycleColumns = PixelFont.width(of: text) + gapColumns
                    let step = Int(context.date.timeIntervalSinceReferenceDate * pixelsPerSecond) % max(cycleColumns, 1)
                    let offset = overflows ? -CGFloat(step) * snapped : 0

                    HStack(spacing: CGFloat(gapColumns) * snapped) {
                        PixelText(text, pixel: snapped)
                        if overflows { PixelText(text, pixel: snapped) }
                    }
                    .fixedSize()
                    .offset(x: offset)
                }
            }
            .clipped()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { boxWidth = $0 }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}

#Preview {
    VStack(spacing: 24) {
        TrackInfoStrip(text: "Song")
        TrackInfoStrip(text: "A very long song title that has to scroll — Some Artist")
    }
    .playerPreview()
}

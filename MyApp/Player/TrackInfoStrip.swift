import SwiftUI

/// Dot-matrix "now playing" block: "♥ TITLE — ARTIST ♥" (scrolling in pixel steps when it
/// doesn't fit) with an optional footer — the timeline — inside the same display.
struct TrackInfoStrip<Footer: View>: View {
    let text: String
    /// Size multiplier for the title text.
    var scale: CGFloat = 1
    /// Edge-to-edge panel: spans the full width, and its background runs down under the home indicator.
    var isFullBleed = false
    @ViewBuilder var footer: () -> Footer

    @Environment(\.pixelUnit) private var unit

    var body: some View {
        let pixel = unit * scale
        VStack(spacing: unit * 8) {
            HStack(spacing: pixel * 3) {
                PixelText("♥", pixel: pixel * 1.3 )
                DotMatrixMarquee(text: text, pixel: pixel)
                PixelText("♥", pixel: pixel * 1.3 )
            }
            .foregroundStyle(RetroTheme.lcdText)
            .lcdGlow()
            .padding(.horizontal, unit * 4)
            .padding(.top, unit * 5)

            footer()
        }
        // Full-bleed adds the player's side margin, so content lines up with the controls above.
        .padding(.horizontal, unit * (isFullBleed ? 10 : 4))
        .padding(.top, unit * 6)
        .padding(.bottom, unit * 3.5)
        .background {
            if isFullBleed {
                fullBleedPanel
            } else {
                recessedPanel
            }
        }
    }

    private var glass: Color { RetroTheme.lcdGlass.mix(with: .black, by: 0.35) }

    /// Unlit dot grid of the matrix display.
    private var dotGrid: some View {
        DotGrid(pitch: unit)
            .fill(Color.white.opacity(0.05))
            .padding(unit * 2)
    }

    private var recessedPanel: some View {
        PixelNotchedRect(step: unit, steps: 2)
            .fill(glass)
            .overlay { dotGrid }
            .overlay {
                PixelNotchedRect(step: unit, steps: 2)
                    .stroke(Color.black.opacity(0.75), lineWidth: unit)
            }
            // Light metal lip under the recess.
            .shadow(color: .white.opacity(0.15), radius: 0, y: 1)
    }

    /// No side or bottom borders — only a dark top edge with a light lip above it.
    private var fullBleedPanel: some View {
        Rectangle()
            .fill(glass)
            .overlay { dotGrid }
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.black.opacity(0.75))
                    .frame(height: unit)
            }
            .shadow(color: .white.opacity(0.15), radius: 0, y: -1)
            .ignoresSafeArea(edges: [.bottom, .horizontal])
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

#Preview("Title only") {
    TrackInfoStrip(text: "Justin Bieber — Yukon", scale: 1.33) { EmptyView() }
        .playerPreview()
}

#Preview("Full bleed") {
    VStack {
        Spacer()
        TrackInfoStrip(text: "Justin Bieber — Yukon", scale: 1.1, isFullBleed: true) {
            TimelineBar(currentTime: 42, duration: 180, onSeek: { _ in })
        }
    }
    .playerPreview(padding: 0)
}

#Preview("With timeline") {
    TrackInfoStrip(text: "A very long track title that has to scroll — Artist", scale: 1.33) {
        TimelineBar(currentTime: 42, duration: 180, onSeek: { _ in })
    }
    .playerPreview()
}

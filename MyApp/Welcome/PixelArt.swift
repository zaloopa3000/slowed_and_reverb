import SwiftUI

/// Twinkling, slowly drifting pixel stars. Updates at 12 fps on purpose — choppy like 8-bit hardware.
struct PixelStarfield: View {
    /// Size of one star pixel in points.
    var unit: CGFloat = 2

    private struct Star {
        let x: Double
        let y: Double
        let size: Int
        let color: Color
        let phase: Double
        let rate: Double
        let drift: Double
    }

    @State private var stars: [Star] = PixelStarfield.makeStars(count: 80)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            Canvas { canvas, size in
                for star in stars {
                    let blink = sin(time * star.rate + star.phase)
                    guard blink > -0.55 else { continue } // star is "off" this frame

                    let y = (star.y + time * star.drift).truncatingRemainder(dividingBy: 1)
                    // Snap positions to the pixel grid so stars never land between pixels.
                    let px = (star.x * size.width / unit).rounded() * unit
                    let py = (y * size.height / unit).rounded() * unit
                    let side = unit * CGFloat(star.size)
                    let color = star.color.opacity(blink > 0.1 ? 1 : 0.45)

                    canvas.fill(Path(CGRect(x: px, y: py, width: side, height: side)), with: .color(color))

                    // Big stars flare into a "+" sparkle at their brightest.
                    if star.size == 2, blink > 0.92 {
                        canvas.fill(Path(CGRect(x: px - unit, y: py + unit / 2, width: side + unit * 2, height: unit)), with: .color(color))
                        canvas.fill(Path(CGRect(x: px + unit / 2, y: py - unit, width: unit, height: side + unit * 2)), with: .color(color))
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }

    private static func makeStars(count: Int) -> [Star] {
        let palette: [Color] = [
            RetroTheme.Arcade.white, RetroTheme.Arcade.white, RetroTheme.Arcade.white,
            RetroTheme.Arcade.yellow, RetroTheme.Arcade.red, RetroTheme.Arcade.blue
        ]
        return (0..<count).map { _ in
            Star(
                x: .random(in: 0...1),
                y: .random(in: 0...1),
                size: Double.random(in: 0...1) < 0.2 ? 2 : 1,
                color: palette.randomElement() ?? RetroTheme.Arcade.white,
                phase: .random(in: 0...(2 * .pi)),
                rate: .random(in: 0.8...3.2),
                drift: .random(in: 0.004...0.012)
            )
        }
    }
}

/// Title logo in chunky pixel letters with a banded, dithered face and a solid extrusion.
struct ExtrudedPixelLogo: View {
    let lines: [String]
    /// Size of one logo pixel in points.
    let pixel: CGFloat
    var depth = 3

    var body: some View {
        VStack(spacing: pixel * 2) {
            ForEach(lines, id: \.self) { line in
                ExtrudedPixelLine(text: line, pixel: pixel, depth: depth)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(lines.joined(separator: " "))
    }

    /// Largest pixel size (in whole even device pixels) that fits `lines` into the given box.
    static func fittingPixel(for lines: [String], width: CGFloat, height: CGFloat, depth: Int = 3, scale: CGFloat) -> CGFloat {
        let columns = CGFloat(lines.map { PixelFont.width(of: $0, bold: true) }.max() ?? 1)
        let rows = CGFloat(lines.count * (PixelFont.glyphHeight + depth) + (lines.count - 1) * 2)
        let raw = min(width / columns, height / rows)
        // Even device pixels, so half-pixel dithering stays crisp.
        let devicePixels = max((raw * scale / 2).rounded(.down) * 2, 2)
        return devicePixels / scale
    }
}

private struct ExtrudedPixelLine: View {
    let text: String
    let pixel: CGFloat
    let depth: Int

    private typealias Palette = RetroTheme.Arcade

    var body: some View {
        let width = CGFloat(PixelFont.width(of: text, bold: true)) * pixel
        let height = CGFloat(PixelFont.glyphHeight) * pixel
        let shape = PixelTextShape(text: text, pixel: pixel, bold: true)

        TimelineView(.periodic(from: .now, by: 1.0 / 20)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            // Logo bobs one pixel up and down in hard steps.
            let bob: CGFloat = Int(time * 1.6).isMultiple(of: 2) ? 0 : -pixel

            ZStack(alignment: .topLeading) {
                // Extrusion: stacked copies, darkest at the back.
                ForEach((1...depth).reversed(), id: \.self) { layer in
                    shape
                        .fill(layer == depth ? Palette.logoShadowDeep : Palette.logoShadow)
                        .offset(y: CGFloat(layer) * pixel)
                }

                // Face: three hard color bands, matching glyph rows (3 / 2 / 2).
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: Palette.logoLight, location: 0),
                            .init(color: Palette.logoLight, location: 3 / 7),
                            .init(color: Palette.logoMid, location: 3 / 7),
                            .init(color: Palette.logoMid, location: 5 / 7),
                            .init(color: Palette.logoDeep, location: 5 / 7),
                            .init(color: Palette.logoDeep, location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

                // Checkerboard dither on the rows just above each band change.
                ZStack(alignment: .topLeading) {
                    DitherPattern(cell: pixel / 2)
                        .fill(Palette.logoMid)
                        .frame(width: width, height: pixel)
                        .offset(y: pixel * 2)
                    DitherPattern(cell: pixel / 2)
                        .fill(Palette.logoDeep)
                        .frame(width: width, height: pixel)
                        .offset(y: pixel * 4)
                    shine(time: time, width: width, height: height)
                }
                .frame(width: width, height: height, alignment: .topLeading)
                .mask(shape)
            }
            .offset(y: bob)
        }
        .frame(width: width, height: height + CGFloat(depth) * pixel, alignment: .topLeading)
    }

    /// A 2-pixel white band sweeping across the face every few seconds, in pixel steps.
    private func shine(time: TimeInterval, width: CGFloat, height: CGFloat) -> some View {
        let period = 3.6
        let sweep = 0.9
        let phase = time.truncatingRemainder(dividingBy: period) / sweep
        let travel = width + pixel * 8
        let x = phase <= 1 ? (CGFloat(phase) * travel / pixel).rounded() * pixel - pixel * 4 : -pixel * 10
        return Rectangle()
            .fill(Color.white.opacity(0.75))
            .frame(width: pixel * 2, height: height)
            .offset(x: x)
    }
}

/// 28×18 pixel-art cassette with reels that spin in two-frame steps.
struct PixelCassetteSprite: View {
    /// Size of one sprite pixel in points.
    let cell: CGFloat
    var framesPerSecond: Double = 6

    static let columns = 28
    static let rows = 18

    private static let outline = Color(red: 0.06, green: 0.04, blue: 0.09)
    private static let body = Color(red: 0.36, green: 0.42, blue: 0.88)
    private static let bodyLight = Color(red: 0.62, green: 0.68, blue: 1.0)
    private static let bodyShade = Color(red: 0.2, green: 0.25, blue: 0.62)
    private static let label = RetroTheme.Arcade.red
    private static let labelLight = Color(red: 1.0, green: 0.6, blue: 0.5)
    private static let cream = Color(red: 0.96, green: 0.91, blue: 0.78)
    private static let window = Color(red: 0.1, green: 0.07, blue: 0.14)
    private static let tape = Color(red: 0.32, green: 0.2, blue: 0.16)
    private static let reel = RetroTheme.Arcade.white

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1 / framesPerSecond)) { context in
            let frame = Int(context.date.timeIntervalSinceReferenceDate * framesPerSecond) % 2
            Canvas { canvas, _ in
                func fill(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: Color) {
                    canvas.fill(
                        Path(CGRect(x: CGFloat(x) * cell, y: CGFloat(y) * cell, width: CGFloat(w) * cell, height: CGFloat(h) * cell)),
                        with: .color(color)
                    )
                }

                // Shell with cut corners, highlight and shade.
                fill(1, 0, 26, 18, Self.outline)
                fill(0, 1, 28, 16, Self.outline)
                fill(1, 1, 26, 16, Self.body)
                fill(2, 1, 24, 1, Self.bodyLight)
                fill(1, 2, 1, 14, Self.bodyLight)
                fill(1, 16, 26, 1, Self.bodyShade)
                for (x, y) in [(2, 2), (25, 2), (2, 15), (25, 15)] {
                    fill(x, y, 1, 1, Self.outline) // screws
                }

                // Label with writing lines.
                fill(3, 2, 22, 10, Self.label)
                fill(3, 2, 22, 1, Self.labelLight)
                fill(5, 3, 18, 1, Self.cream)
                fill(5, 11, 18, 1, Self.label.mix(with: .black, by: 0.3))

                // Tape window and the tape running between the reels.
                fill(6, 5, 16, 5, Self.window)
                fill(10, 9, 8, 1, Self.tape)

                reel(at: 7, 5, frame: frame, fill: fill)
                reel(at: 16, 5, frame: frame, fill: fill)

                // Bottom guide with head holes.
                fill(6, 13, 16, 3, Self.bodyShade)
                fill(7, 12, 14, 1, Self.bodyShade)
                fill(9, 14, 2, 2, Self.outline)
                fill(17, 14, 2, 2, Self.outline)
                fill(13, 14, 2, 1, Self.outline)
            }
        }
        .frame(width: CGFloat(Self.columns) * cell, height: CGFloat(Self.rows) * cell)
        .accessibilityHidden(true)
    }

    /// 5×5 reel hub: a ring plus spokes that alternate between "+" and "×".
    private func reel(at x: Int, _ y: Int, frame: Int, fill: (Int, Int, Int, Int, Color) -> Void) {
        let ring = [(1, 0), (2, 0), (3, 0), (0, 1), (4, 1), (0, 2), (4, 2), (0, 3), (4, 3), (1, 4), (2, 4), (3, 4)]
        let spokes = frame == 0
            ? [(2, 1), (2, 3), (1, 2), (3, 2)]
            : [(1, 1), (3, 3), (1, 3), (3, 1)]
        for (dx, dy) in ring + spokes {
            fill(x + dx, y + dy, 1, 1, Self.reel)
        }
    }
}

/// Text that blinks on/off in hard steps (no fading), like "PRESS START".
struct BlinkingPixelText: View {
    let text: String
    var pixel: CGFloat = 2
    var interval: Double = 0.5

    var body: some View {
        TimelineView(.periodic(from: .now, by: interval)) { context in
            let visible = Int(context.date.timeIntervalSinceReferenceDate / interval).isMultiple(of: 2)
            PixelText(text, pixel: pixel)
                .opacity(visible ? 1 : 0)
        }
        .accessibilityElement()
        .accessibilityLabel(text)
    }
}

#Preview("Logo & cassette") {
    VStack(spacing: 32) {
        ExtrudedPixelLogo(lines: ["SLOWED", "+REVERB"], pixel: 6)
        PixelCassetteSprite(cell: 6)
        BlinkingPixelText(text: "Insert a song to start", pixel: 2)
            .foregroundStyle(RetroTheme.Arcade.yellow)
    }
    .padding(24)
    .background(RetroTheme.Arcade.background)
}

#Preview("Starfield") {
    PixelStarfield()
        .background(RetroTheme.Arcade.background)
        .ignoresSafeArea()
}

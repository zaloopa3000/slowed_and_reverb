import SwiftUI

/// Night-time retro-punk palette shared by the player, splash and welcome screens:
/// deep indigo body, dark violet plastic, neon cyan text and a hot pink accent.
enum RetroTheme {
    // MARK: Colors

    /// Device body: deep night gradient, same family as the arcade background.
    static let bodyHighlight = Color(red: 0.13, green: 0.09, blue: 0.22)
    static let body = Color(red: 0.08, green: 0.06, blue: 0.15)
    static let bodyShadow = Color(red: 0.04, green: 0.03, blue: 0.08)

    /// Dark plastic for recesses / housings, and the lighter plastic of the keys.
    static let plasticDark = Color(red: 0.05, green: 0.04, blue: 0.09)
    static let plastic = Color(red: 0.17, green: 0.14, blue: 0.27)

    /// Dark display glass and its lit neon pixels.
    static let lcdGlass = Color(red: 0.05, green: 0.05, blue: 0.1)
    static let lcdText = Color(red: 0.55, green: 0.9, blue: 1.0)

    /// Hot neon pink accent (LED, playhead, lit groove, heart).
    static let accentRed = Color(red: 1.0, green: 0.3, blue: 0.52)
    /// Secondary neon for glows and gradients.
    static let neonViolet = Color(red: 0.62, green: 0.48, blue: 1.0)

    /// Light lavender for regular labels.
    static let text = Color(red: 0.8, green: 0.78, blue: 0.95)

    /// 8-bit arcade palette (welcome screen, pixel accents).
    enum Arcade {
        static let background = Color(red: 0.11, green: 0.08, blue: 0.15)
        static let white = Color(red: 0.94, green: 0.92, blue: 0.97)
        static let blue = Color(red: 0.55, green: 0.6, blue: 0.96)
        static let red = Color(red: 0.92, green: 0.41, blue: 0.35)
        static let yellow = Color(red: 0.97, green: 0.89, blue: 0.42)

        /// Logo face bands, light → deep.
        static let logoLight = Color(red: 0.72, green: 0.78, blue: 1.0)
        static let logoMid = Color(red: 0.42, green: 0.52, blue: 0.95)
        static let logoDeep = Color(red: 0.27, green: 0.33, blue: 0.82)
        static let logoShadow = Color(red: 0.14, green: 0.15, blue: 0.45)
        static let logoShadowDeep = Color(red: 0.09, green: 0.08, blue: 0.28)
    }
}

extension EnvironmentValues {
    /// Base pixel size (pt) for pixel-font UI, derived from the screen size by the root view.
    @Entry var pixelUnit: CGFloat = 2
}

extension View {
    /// Soft phosphor glow for lit LCD / dot-matrix pixels.
    func lcdGlow(_ color: Color = RetroTheme.lcdText, radius: CGFloat = 3) -> some View {
        shadow(color: color.opacity(0.55), radius: radius)
    }
}

/// Fine horizontal lines for an LCD / CRT texture.
struct Scanlines: View {
    var spacing: CGFloat = 3

    var body: some View {
        Canvas { context, size in
            var y: CGFloat = 0
            while y < size.height {
                context.fill(
                    Path(CGRect(x: 0, y: y, width: size.width, height: 1)),
                    with: .color(.black)
                )
                y += spacing
            }
        }
        .allowsHitTesting(false)
    }
}

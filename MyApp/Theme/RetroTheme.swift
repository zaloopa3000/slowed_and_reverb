import SwiftUI

/// Night-time retro-punk palette shared by the player, splash and welcome screens:
/// deep indigo body, dark violet plastic, neon cyan text and a hot pink accent.
enum RetroTheme {
    // MARK: Colors

    /// Device body: deep night gradient, same family as the arcade background.
    static let bodyHighlight = Color(#colorLiteral(red: 0.13, green: 0.09, blue: 0.22, alpha: 1))
    static let body = Color(#colorLiteral(red: 0.08, green: 0.06, blue: 0.15, alpha: 1))
    static let bodyShadow = Color(#colorLiteral(red: 0.04, green: 0.03, blue: 0.08, alpha: 1))

    /// Dark plastic for recesses / housings, and the lighter plastic of the keys.
    static let plasticDark = Color(#colorLiteral(red: 0.05, green: 0.04, blue: 0.09, alpha: 1))
    static let plastic = Color(#colorLiteral(red: 0.17, green: 0.14, blue: 0.27, alpha: 1))

    /// Dark display glass and its lit neon pixels.
    static let lcdGlass = Color(#colorLiteral(red: 0.05, green: 0.05, blue: 0.1, alpha: 1))
    static let lcdText = Color(#colorLiteral(red: 0.55, green: 0.9, blue: 1.0, alpha: 1))

    /// Hot neon pink accent (LED, playhead, lit groove, heart).
    static let accentRed = Color(#colorLiteral(red: 1.0, green: 0.3, blue: 0.52, alpha: 1))
    /// Secondary neon for glows and gradients.
    static let neonViolet = Color(#colorLiteral(red: 0.62, green: 0.48, blue: 1, alpha: 1))

    /// Light lavender for regular labels.
    static let text = Color(#colorLiteral(red: 0.8, green: 0.78, blue: 0.95, alpha: 1))

    /// 8-bit arcade palette (welcome screen, pixel accents).
    enum Arcade {
        static let background = Color(#colorLiteral(red: 0.11, green: 0.08, blue: 0.15, alpha: 1))
        static let white = Color(#colorLiteral(red: 0.94, green: 0.92, blue: 0.97, alpha: 1))
        static let blue = Color(#colorLiteral(red: 0.55, green: 0.6, blue: 0.96, alpha: 1))
        static let red = Color(#colorLiteral(red: 0.92, green: 0.41, blue: 0.35, alpha: 1))
        static let yellow = Color(#colorLiteral(red: 0.97, green: 0.89, blue: 0.42, alpha: 1))

        /// Logo face bands, light → deep.
        static let logoLight = Color(#colorLiteral(red: 0.72, green: 0.78, blue: 1.0, alpha: 1))
        static let logoMid = Color(#colorLiteral(red: 0.42, green: 0.52, blue: 0.95, alpha: 1))
        static let logoDeep = Color(#colorLiteral(red: 0.27, green: 0.33, blue: 0.82, alpha: 1))
        static let logoShadow = Color(#colorLiteral(red: 0.14, green: 0.15, blue: 0.45, alpha: 1))
        static let logoShadowDeep = Color(#colorLiteral(red: 0.09, green: 0.08, blue: 0.28, alpha: 1))
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

extension View {
    /// Wraps a component for Xcode previews: the player's pixel unit and night background.
    func playerPreview(padding: CGFloat = 20) -> some View {
        self
            .environment(\.pixelUnit, 2)
            .padding(padding)
            .background(RetroTheme.body)
    }
}

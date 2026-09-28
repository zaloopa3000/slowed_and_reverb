import SwiftUI

/// Launch screen: pixel cassette logo and app name, centered.
struct SplashView: View {
    @State private var appeared = false
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let unit = PixelText.snappedDown(min(geo.size.width / 196, geo.size.height / 380), scale: displayScale)

            VStack(spacing: unit * 10) {
                PixelCassetteSprite(cell: unit * 2.5)

                VStack(spacing: unit * 5) {
                    PixelText("Slowed + Reverb", pixel: unit * 1.5)
                        .foregroundStyle(RetroTheme.Arcade.white)
                        .pixelShadow(RetroTheme.Arcade.logoShadowDeep, offset: unit)
                    PixelText("Cassette Player", pixel: unit)
                        .foregroundStyle(RetroTheme.Arcade.blue)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            // Hard "power on" pop instead of a smooth fade.
            .opacity(appeared ? 1 : 0)
        }
        .background(RetroTheme.Arcade.background.ignoresSafeArea())
        // Show immediately: the launch screen already has the same background color.
        .onAppear { appeared = true }
    }
}

#Preview {
    SplashView()
}

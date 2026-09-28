import SwiftUI

/// Player background: a heavily blurred color field from the current GIF,
/// seen through the semi-transparent night body, so the controls pick up the GIF's tones.
/// Keeps the previous tint while the next GIF loads, then crossfades to the new one.
struct GifAmbientBackdrop: View {
    let gif: AnimatedGIF?
    /// Channel number; changes whenever a new GIF is tuned in.
    let channel: Int

    /// Opacity of the night body over the GIF tint: 1 hides the tint, 0 shows it at full strength.
    static let bodyOpacity: Double = 0.85

    @State private var ambience: CGImage?
    @State private var ambienceID = 0

    var body: some View {
        ZStack {
            RetroTheme.bodyShadow

            ZStack {
                if let ambience {
                    Image(decorative: ambience, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .blur(radius: 24)
                        .id(ambienceID)
                        .transition(.opacity)
                }
            }
            .opacity(0.8)

            NightBody(opacity: ambience == nil ? 1 : Self.bodyOpacity)
        }
        .task(id: AmbienceKey(channel: channel, hasGIF: gif != nil)) {
            guard let gif else { return }
            let thumbnail = GifAmbience.thumbnail(of: GifAmbience.sourceFrame(of: gif))
            withAnimation(.easeInOut(duration: 0.6)) {
                ambience = thumbnail
                ambienceID &+= 1
            }
        }
    }

    private struct AmbienceKey: Equatable {
        let channel: Int
        let hasGIF: Bool
    }
}

/// Night-time body: deep indigo gradient, faint pixel stars, and a soft pink glow at the bottom.
/// `opacity` applies to the gradient only, letting the ambience show through.
private struct NightBody: View {
    var opacity: Double = 1
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RetroTheme.bodyHighlight, RetroTheme.body, RetroTheme.bodyShadow],
                startPoint: .top,
                endPoint: .bottom
            )
            .opacity(opacity)
            PixelStarfield(unit: PixelText.snapped(1.5, scale: displayScale))
                .opacity(0.35)
            RadialGradient(
                colors: [RetroTheme.accentRed.opacity(0.22), .clear],
                center: .bottom,
                startRadius: 0,
                endRadius: 320
            )
        }
    }
}

#Preview {
    // No GIF: looks like the plain night body.
    GifAmbientBackdrop(gif: nil, channel: 0)
        .frame(height: 400)
        .playerPreview(padding: 0)
}

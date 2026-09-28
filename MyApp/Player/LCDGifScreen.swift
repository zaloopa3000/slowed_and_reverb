import SwiftUI

/// Full-bleed anime GIF at the top of the player, clean by default.
/// Two clear glass buttons in the bottom corners: cycle an optional overlay effect
/// (Pixel / CRT / VHS / Neon) and load the next random anime GIF.
/// Static noise fills the screen while the next GIF loads.
/// The GIF plays at the track's speed while music is playing, so slowed tracks look slowed too.
struct LCDGifScreen: View {
    let channel: GifChannel
    /// Playback rate of the GIF (1 = normal).
    let rate: Double
    /// Height of the status bar area the GIF runs under; overlays stay below it.
    var topInset: CGFloat = 0

    @State private var clock = GifClock()
    /// Remembered between launches; clean by default.
    @AppStorage("gifEffect") private var effect: GifEffect = .none
    @State private var isEffectNameVisible = false
    @Environment(\.pixelUnit) private var unit

    var body: some View {
        ZStack {
            Color.black

            switch channel.state {
            case .showing(let gif):
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
                    let time = clock.advance(to: context.date, rate: rate)
                    // Clear box sets the size; the fill-scaled frame can't inflate it.
                    Color.clear.overlay {
                        Image(decorative: gif.frame(at: time), scale: 1)
                            .resizable()
                            .scaledToFill()
                    }
                    .clipped()
                    .gifEffect(effect, time: context.date.timeIntervalSinceReferenceDate, pixelSize: unit * 4)
                }
                .accessibilityLabel("Anime GIF")
            case .idle, .tuning:
                StaticNoise(pixel: unit * 1.5)
            case .noSignal:
                ZStack {
                    StaticNoise(pixel: unit * 1.5).opacity(0.35)
                    VStack(spacing: unit * 3) {
                        BlinkingPixelText(text: "No signal", pixel: unit * 1.25, interval: 0.6)
                        PixelText("Tap next to retune", pixel: unit * 0.6)
                            .opacity(0.7)
                    }
                    .foregroundStyle(RetroTheme.lcdText)
                    .lcdGlow()
                }
            }
        }
        // Bottom ~15% melts into the ambient backdrop below; overlays stay crisp.
        .mask {
            LinearGradient(
                stops: [.init(color: .black, location: 0.85), .init(color: .clear, location: 1)],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        // Light shade under the status bar so the clock / battery stay readable on bright GIFs.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: topInset + unit * 6)
                .allowsHitTesting(false)
        }
        .overlay(alignment: .bottom) { controls }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: channel.number)
        .sensoryFeedback(.selection, trigger: effect)
        .task { channel.tuneInIfNeeded() }
    }

    /// Effect button (left), GIPHY attribution (center), next-GIF button (right).
    private var controls: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: unit * 2) {
                if isEffectNameVisible {
                    PixelText(effect.title, pixel: unit * 0.75)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, unit * 3)
                        .padding(.vertical, unit * 2)
                        .background(Capsule().fill(Color.black.opacity(0.45)))
                        .transition(.opacity)
                }
                glassButton(systemImage: "camera.filters", label: "Change effect, now \(effect.title)") {
                    effect = effect.next
                    showEffectName()
                }
            }

            Spacer()

            // Attribution required by the GIPHY API terms.
            PixelText("Giphy", pixel: unit * 0.5)
                .foregroundStyle(Color.white.opacity(0.6))
                .shadow(color: .black.opacity(0.8), radius: 1)
                .padding(.bottom, unit * 2)

            Spacer()

            glassButton(systemImage: "shuffle", label: "Next GIF") {
                channel.nextChannel()
            }
        }
        .padding(unit * 4)
        .animation(.easeInOut(duration: 0.2), value: isEffectNameVisible)
    }

    private func glassButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass(.clear))
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
    }

    private func showEffectName() {
        isEffectNameVisible = true
        let shown = effect
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            // Only hide if no newer tap re-showed it with another effect.
            if effect == shown { isEffectNameVisible = false }
        }
    }
}

/// Accumulates GIF playback time at a variable rate, so speed changes never jump frames.
/// A plain class on purpose: advanced from the timeline's render pass.
final class GifClock {
    private var lastDate: Date?
    private var time: TimeInterval = 0

    func advance(to date: Date, rate: Double) -> TimeInterval {
        let dt = min(max(date.timeIntervalSince(lastDate ?? date), 0), 0.1)
        lastDate = date
        time += dt * rate
        return time
    }
}

/// Analog-TV static in chunky pixels, redrawn at 15 fps (shown only while loading).
struct StaticNoise: View {
    let pixel: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 15)) { context in
            // New pattern each frame, deterministic within a frame.
            var generator = SplitMix64(seed: UInt64(context.date.timeIntervalSinceReferenceDate * 15))
            Canvas { canvas, size in
                let columns = Int(size.width / pixel) + 1
                let rows = Int(size.height / pixel) + 1
                for row in 0..<rows {
                    for column in 0..<columns {
                        let brightness = Double(generator.next() % 256) / 255
                        canvas.fill(
                            Path(CGRect(x: CGFloat(column) * pixel, y: CGFloat(row) * pixel, width: pixel, height: pixel)),
                            with: .color(Color(white: brightness * 0.85))
                        )
                    }
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// Tiny fast PRNG so noise frames are cheap and reproducible.
private struct SplitMix64 {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

#Preview {
    // Loads a real GIF from GIPHY, so it needs network access.
    LCDGifScreen(channel: GifChannel(), rate: 1)
        .frame(height: 320)
        .playerPreview(padding: 0)
}

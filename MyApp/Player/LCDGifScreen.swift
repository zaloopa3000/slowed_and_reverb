import SwiftUI

/// Full-bleed anime GIF at the top of the player, shown clean (no retro filters on top).
/// Tap to switch to another random GIF; static noise fills the screen while the next one loads.
/// The GIF plays at the track's speed while music is playing, so slowed tracks look slowed too.
struct LCDGifScreen: View {
    let channel: GifChannel
    /// Playback rate of the GIF (1 = normal).
    let rate: Double
    /// Height of the status bar area the GIF runs under; overlays stay below it.
    var topInset: CGFloat = 0

    @State private var clock = GifClock()
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
                }
            case .idle, .tuning:
                StaticNoise(pixel: unit * 1.5)
            case .noSignal:
                ZStack {
                    StaticNoise(pixel: unit * 1.5).opacity(0.35)
                    VStack(spacing: unit * 3) {
                        BlinkingPixelText(text: "No signal", pixel: unit * 1.25, interval: 0.6)
                        PixelText("Tap to retune", pixel: unit * 0.6)
                            .opacity(0.7)
                    }
                    .foregroundStyle(RetroTheme.lcdText)
                    .lcdGlow()
                }
            }
        }
        // Light shade under the status bar so the clock / battery stay readable on bright GIFs.
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: topInset + unit * 6)
                .allowsHitTesting(false)
        }
        // Attribution required by the GIPHY API terms.
        .overlay(alignment: .bottomTrailing) {
            PixelText("Giphy", pixel: unit * 0.5)
                .foregroundStyle(Color.white.opacity(0.6))
                .shadow(color: .black.opacity(0.8), radius: 1)
                .padding(unit * 2)
        }
        .contentShape(Rectangle())
        .onTapGesture { channel.nextChannel() }
        .sensoryFeedback(.impact(weight: .light, intensity: 0.7), trigger: channel.number)
        .task { channel.tuneInIfNeeded() }
        .accessibilityElement()
        .accessibilityLabel("Anime GIF")
        .accessibilityHint("Double-tap for another GIF")
        .accessibilityAddTraits(.isButton)
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
            let seed = UInt64(context.date.timeIntervalSinceReferenceDate * 15)
            Canvas { canvas, size in
                let columns = Int(size.width / pixel) + 1
                let rows = Int(size.height / pixel) + 1
                guard let noise = Self.noiseImage(columns: columns, rows: rows, seed: seed) else { return }
                // One tiny image, scaled up without smoothing, instead of thousands of rects per frame.
                canvas.draw(
                    Image(decorative: noise, scale: 1).interpolation(.none),
                    in: CGRect(x: 0, y: 0, width: CGFloat(columns) * pixel, height: CGFloat(rows) * pixel)
                )
            }
        }
        .accessibilityHidden(true)
    }

    /// Grayscale image with one random pixel per noise cell, capped at 85% white.
    nonisolated static func noiseImage(columns: Int, rows: Int, seed: UInt64) -> CGImage? {
        guard columns > 0, rows > 0 else { return nil }
        var generator = SplitMix64(seed: seed)
        var bytes = [UInt8](repeating: 0, count: columns * rows)
        for index in bytes.indices {
            bytes[index] = UInt8(Double(generator.next() % 256) * 0.85)
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(
            width: columns,
            height: rows,
            bitsPerComponent: 8,
            bitsPerPixel: 8,
            bytesPerRow: columns,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.none.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }
}

/// Tiny fast PRNG so noise frames are cheap and reproducible.
private nonisolated struct SplitMix64 {
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
    VStack(spacing: 0) {
        LCDGifScreen(channel: GifChannel(), rate: 1)
            .frame(height: 300)
        StaticNoise(pixel: 3)
            .frame(height: 120)
    }
    .playerPreview()
}

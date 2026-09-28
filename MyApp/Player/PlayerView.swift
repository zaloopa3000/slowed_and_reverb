import SwiftUI
import UniformTypeIdentifiers

/// Main player screen, top to bottom:
/// - full-bleed lo-fi GIF: everything above the meter, running under the status bar;
/// - level meter with EJECT / REC, track strip, sliders, timeline, transport;
/// - the animated cassette, slightly wider than the screen and running off its bottom edge.
///
/// Sizes derive from the available width/height: a pixel unit for all pixel-font
/// UI, and a vertical scale that tightens spacing and fixed rows on short screens.
/// The GIF takes whatever height is left, so every screen size stays filled.
struct PlayerView: View {
    @Bindable var engine: AudioEngine
    @State private var isImporterPresented = false
    @State private var gifChannel = GifChannel()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let unit = PixelText.snappedDown(min(geo.size.width / 196, geo.size.height / 380), scale: displayScale)
            // 1.0 on a ~760 pt tall safe area, smaller on shorter screens.
            let vScale = min(max(geo.size.height / 760, 0.78), 1.1)
            let spacing = 10 * vScale
            // The cassette also fills the bottom inset, so the slot inside the safe area is shorter.
            let cassetteSlot = max(
                min(CassetteView.slotHeight(forWidth: geo.size.width) - geo.safeAreaInsets.bottom, geo.size.height * 0.3),
                80
            )

            VStack(spacing: 0) {
                gifArea(topInset: geo.safeAreaInsets.top)

                controls(unit: unit, vScale: vScale, spacing: spacing)
                    .padding(.horizontal, min(20, geo.size.width * 0.05))
                    .padding(.top, spacing * 1.4)
                    .padding(.bottom, spacing)

                // Placeholder for the cassette; the cassette itself extends into the bottom inset.
                Color.clear
                    .frame(height: cassetteSlot)
                    .background {
                        CassetteView(
                            progress: engine.progress,
                            isPlaying: engine.isPlaying,
                            speed: engine.speed,
                            windDirection: engine.windDirection,
                            title: engine.isLoaded ? engine.metadata.title : "Blank tape"
                        )
                        .ignoresSafeArea(edges: .bottom)
                    }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.pixelUnit, unit)
        }
        .background { NightBody().ignoresSafeArea() }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await engine.importTrack(from: url) }
            }
        }
        .alert("Tape Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }

    // MARK: Sections

    /// Takes all remaining height; the GIF itself runs up under the status bar.
    private func gifArea(topInset: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(minHeight: 100)
            .background {
                LCDGifScreen(
                    channel: gifChannel,
                    rate: engine.isPlaying ? Double(engine.speed) : 1,
                    topInset: topInset
                )
                .ignoresSafeArea(edges: .top)
            }
            .overlay(alignment: .bottom) { NeonDivider() }
    }

    private func controls(unit: CGFloat, vScale: CGFloat, spacing: CGFloat) -> some View {
        VStack(spacing: spacing) {
            SpeakerRow(
                meter: engine.meter,
                isPlaying: engine.isPlaying,
                canRecord: false, // Export arrives in stage 7.
                onEject: { isImporterPresented = true },
                onRecord: {},
                height: 86 * vScale
            )

            TrackInfoStrip(text: trackText)

            VStack(spacing: 6 * vScale) {
                SteppedSlider(
                    title: "Speed",
                    value: $engine.speed,
                    range: AudioEngine.speedRange,
                    step: 0.05,
                    majorEvery: 5,
                    detents: [10], // 1.00x
                    valueText: { String(format: "%.2fx", $0) },
                    tickLabel: { value in
                        // "1" → "1.0" so the scale reads 0.5 · 0.75 · 1.0 · 1.25 · 1.5
                        let label = String(format: "%g", value)
                        return label.contains(".") ? label : label + ".0"
                    }
                )

                SteppedSlider(
                    title: "Reverb",
                    value: $engine.reverb,
                    range: AudioEngine.reverbRange,
                    step: 5,
                    majorEvery: 5,
                    valueText: { "\(Int($0.rounded()))%" },
                    tickLabel: { String(format: "%g", $0) }
                )
            }

            TimelineBar(
                currentTime: engine.currentTime,
                duration: engine.duration,
                onSeek: { engine.seek(to: $0) }
            )

            VStack(spacing: unit * 3) {
                NeonBrand()

                TransportButtons(
                    isPlaying: engine.isPlaying,
                    isEnabled: engine.isLoaded,
                    onPlayPause: { engine.togglePlayPause() },
                    onForward: { engine.skip(by: 10) },
                    onRewind: { engine.skip(by: -10) },
                    onStop: { engine.stop() },
                    onWind: { direction in
                        direction == 0 ? engine.stopWinding() : engine.startWinding(direction)
                    },
                    height: 92 * vScale
                )
            }
        }
    }

    private var trackText: String {
        guard engine.isLoaded else { return "No tape — press Eject to load a track" }
        return "\(engine.metadata.title) — \(engine.metadata.artist)"
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )
    }
}

/// Glowing pink → violet → cyan line under the GIF.
private struct NeonDivider: View {
    var body: some View {
        LinearGradient(
            colors: [RetroTheme.accentRed, RetroTheme.neonViolet, RetroTheme.lcdText],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1.5)
        .shadow(color: RetroTheme.neonViolet.opacity(0.9), radius: 4)
        .shadow(color: RetroTheme.accentRed.opacity(0.5), radius: 10)
        .allowsHitTesting(false)
    }
}

/// Model name above the transport, printed in soft neon.
private struct NeonBrand: View {
    @Environment(\.pixelUnit) private var unit

    var body: some View {
        HStack {
            PixelText("Slowed+Reverb", pixel: unit * 0.9, bold: true)
                .foregroundStyle(RetroTheme.neonViolet.opacity(0.85))
                .lcdGlow(RetroTheme.neonViolet, radius: 4)
            Spacer()
            PixelText("SR-90 Stereo", pixel: unit * 0.6)
                .foregroundStyle(RetroTheme.lcdText.opacity(0.55))
        }
        .padding(.horizontal, 4)
        .accessibilityHidden(true)
    }
}

/// Night-time body: deep indigo gradient, faint pixel stars, and a pink glow behind the cassette.
private struct NightBody: View {
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [RetroTheme.bodyHighlight, RetroTheme.body, RetroTheme.bodyShadow],
                startPoint: .top,
                endPoint: .bottom
            )
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
    PlayerView(engine: AudioEngine())
}

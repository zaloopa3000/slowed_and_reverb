import SwiftUI
import UniformTypeIdentifiers

/// Main player screen, top to bottom:
/// 1. full-width GIF, ~40% of the screen, running under the status bar;
/// 2. L/R meter, LED, EJECT and REC;
/// 3. Speed and Reverb sliders;
/// 4. one block: track title, timeline, transport keys;
/// 5. the brand line.
///
/// Sizes derive from the available width/height: a pixel unit for all pixel-font
/// UI, and a vertical scale for fixed rows. Leftover height is split evenly between spacers.
struct PlayerView: View {
    @Bindable var engine: AudioEngine
    @State private var isImporterPresented = false
    @State private var gifChannel = GifChannel()
    @State private var exporter = TrackExporter()
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geo in
            let unit = PixelText.snappedDown(min(geo.size.width / 196, geo.size.height / 380), scale: displayScale)
            // 1.0 on a ~760 pt tall safe area, smaller on shorter screens.
            let vScale = min(max(geo.size.height / 760, 0.78), 1.1)
            // 40% of the whole screen, status bar included (the GIF runs under it).
            let gifHeight = max((geo.size.height + geo.safeAreaInsets.top) * 0.4 - geo.safeAreaInsets.top, 100)

            VStack(spacing: 0) {
                gifArea(topInset: geo.safeAreaInsets.top)
                    .frame(height: gifHeight)

                controls(unit: unit, vScale: vScale)
                    .padding(.horizontal, min(20, geo.size.width * 0.05))
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .environment(\.pixelUnit, unit)
        }
        .background { NightBody().ignoresSafeArea() }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
            if case .success(let url) = result {
                Task { await engine.importTrack(from: url) }
            }
        }
        .sheet(item: $exporter.exported) { file in
            ShareSheet(url: file.url) { exporter.exported = nil }
                .presentationDetents([.medium, .large])
        }
        .alert("Tape Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorText ?? "")
        }
    }

    // MARK: Sections

    /// The GIF itself runs up under the status bar; the recording overlay covers it while exporting.
    private func gifArea(topInset: CGFloat) -> some View {
        Color.clear
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                LCDGifScreen(
                    channel: gifChannel,
                    rate: engine.isPlaying ? Double(engine.speed) : 1,
                    topInset: topInset
                )
                .ignoresSafeArea(edges: .top)
            }
            .overlay {
                if exporter.isRecording {
                    RecordingOverlay(progress: exporter.progress)
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) { NeonDivider() }
            .animation(.easeInOut(duration: 0.2), value: exporter.isRecording)
    }

    private func controls(unit: CGFloat, vScale: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: unit * 3)

            SpeakerRow(
                meter: engine.meter,
                isPlaying: engine.isPlaying,
                canRecord: engine.isLoaded,
                isRecording: exporter.isRecording,
                onEject: { isImporterPresented = true },
                onRecord: toggleRecording,
                height: 70 * vScale
            )

            Spacer(minLength: unit * 3)

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

            Spacer(minLength: unit * 3)

            // Track title, timeline and keys read as one deck block.
            VStack(spacing: unit * 4) {
                TrackInfoStrip(text: trackText)

                TimelineBar(
                    currentTime: engine.currentTime,
                    duration: engine.duration,
                    onSeek: { engine.seek(to: $0) }
                )

                TransportButtons(
                    isPlaying: engine.isPlaying,
                    isEnabled: engine.isLoaded,
                    onPlayPause: { engine.togglePlayPause() },
                    onForward: { engine.skip(by: 10) },
                    onRewind: { engine.skip(by: -10) },
                    onStop: { engine.stop() },
                    onWind: { direction in
                        if direction == 0 {
                            engine.stopWinding()
                        } else {
                            engine.startWinding(direction)
                        }
                    },
                    height: 92 * vScale
                )
            }

            Spacer(minLength: unit * 3)

            NeonBrand()

            Spacer(minLength: unit * 2)
        }
    }

    // MARK: Actions

    /// REC starts rendering the current track with the current settings; pressing it again cancels.
    private func toggleRecording() {
        if exporter.isRecording {
            exporter.cancel()
            return
        }
        guard let source = engine.sourceURL else { return }
        exporter.start(
            source: source,
            title: engine.metadata.title,
            speed: engine.speed,
            reverb: engine.reverb
        )
    }

    // MARK: Helpers

    private var trackText: String {
        guard engine.isLoaded else { return "No tape — press Eject to load a track" }
        return "\(engine.metadata.title) — \(engine.metadata.artist)"
    }

    private var errorText: String? {
        engine.errorMessage ?? exporter.errorMessage
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorText != nil },
            set: { isPresented in
                guard !isPresented else { return }
                engine.errorMessage = nil
                exporter.errorMessage = nil
            }
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

/// Model name at the bottom, printed in soft neon.
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

/// Night-time body: deep indigo gradient, faint pixel stars and a soft pink glow at the bottom.
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

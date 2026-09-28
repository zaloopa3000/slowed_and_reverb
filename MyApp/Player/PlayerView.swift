import SwiftUI
import UniformTypeIdentifiers

/// Main player screen, top to bottom:
/// - full-bleed anime GIF (~40% of the height), running under the status bar;
/// - L/R level meter with EJECT / REC, sliders, now-playing strip + timeline, transport —
///   spread evenly over the remaining height.
///
/// Sizes derive from the available width/height: a pixel unit for all pixel-font
/// UI, and a vertical scale for the fixed rows. Leftover height goes into equal
/// gaps between the controls, so every screen size looks evenly filled.
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

            VStack(spacing: 0) {
                gifArea(topInset: geo.safeAreaInsets.top)
                    .frame(height: max(geo.size.height * 0.4, 120))

                controls(unit: unit, vScale: vScale, sidePadding: min(20, geo.size.width * 0.05))
                    .frame(maxHeight: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .environment(\.pixelUnit, unit)
        }
        .background {
            GifAmbientBackdrop(gif: gifChannel.currentGIF, channel: gifChannel.number)
                .ignoresSafeArea()
        }
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
        .alert("Recording Failed", isPresented: exportErrorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exporter.errorMessage ?? "")
        }
        // Finished tape → system share sheet (Files, AirDrop, messengers…).
        .sheet(item: $exporter.exported) { file in
            ShareSheet(url: file.url) { exporter.exported = nil }
                .presentationDetents([.medium, .large])
                .ignoresSafeArea()
        }
        .sensoryFeedback(.success, trigger: exporter.exported?.id) { _, new in new != nil }
    }

    /// REC: records a video of the current track (current speed / reverb) over the looping GIF
    /// on screen — audio only if no GIF is loaded; pressing again cancels.
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
            reverb: engine.reverb,
            gif: gifChannel.currentGIF
        )
    }

    // MARK: Sections

    /// GIF slot; the GIF itself runs up under the status bar.
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
            .overlay {
                if exporter.isRecording {
                    RecordingOverlay(progress: exporter.progress)
                        .ignoresSafeArea(edges: .top)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: exporter.isRecording)
            .overlay(alignment: .bottom) { NeonDivider() }
    }

    /// Controls separated by equal flexible gaps, so leftover height is spread evenly.
    /// The bottom display block spans the full width and runs down to the screen edge.
    private func controls(unit: CGFloat, vScale: CGFloat, sidePadding: CGFloat) -> some View {
        let minGap = 16 * vScale

        return VStack(spacing: 0) {
            upperControls(vScale: vScale, minGap: minGap)
                .padding(.horizontal, sidePadding)

            // Now playing, timeline, transport keys and brand as one edge-to-edge display block.
            TrackInfoStrip(text: trackText, scale: 1.1, isFullBleed: true) {
                VStack(spacing: 20 * vScale) {
                    TimelineBar(
                        currentTime: engine.currentTime,
                        duration: engine.duration,
                        onSeek: { engine.seek(to: $0) }
                    )
                    .padding(.horizontal, unit * 4)

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
                        height: 92 * vScale,
                        showsHousing: false
                    )

                    NeonBrand()
                }
            }
        }
    }

    /// Level meter row and the Speed / Reverb sliders, with four equal flexible gaps
    /// (above, between each row, below), so free height is spread evenly between them.
    private func upperControls(vScale: CGFloat, minGap: CGFloat) -> some View {
        VStack(spacing: 0) {
            Spacer(minLength: minGap)

            SpeakerRow(
                meter: engine.meter,
                isPlaying: engine.isPlaying,
                canRecord: engine.isLoaded,
                isRecording: exporter.isRecording,
                onEject: { isImporterPresented = true },
                onRecord: toggleRecording,
                height: 64 * vScale
            )

            Spacer(minLength: minGap)

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

            Spacer(minLength: minGap)

            SteppedSlider(
                title: "Reverb",
                value: $engine.reverb,
                range: AudioEngine.reverbRange,
                step: 5,
                majorEvery: 5,
                valueText: { "\(Int($0.rounded()))%" },
                tickLabel: { String(format: "%g", $0) }
            )

            Spacer(minLength: minGap)
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

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exporter.errorMessage != nil },
            set: { if !$0 { exporter.errorMessage = nil } }
        )
    }
}

/// Thin, muted pink → violet → cyan line where the GIF fades into the body.
private struct NeonDivider: View {
    var body: some View {
        LinearGradient(
            colors: [RetroTheme.accentRed, RetroTheme.neonViolet, RetroTheme.lcdText],
            startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: 1)
        .shadow(color: RetroTheme.neonViolet.opacity(0.6), radius: 3)
        .shadow(color: RetroTheme.accentRed.opacity(0.3), radius: 8)
        .opacity(0.55)
        .allowsHitTesting(false)
    }
}

/// Model name under the transport, printed in soft neon.
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

#Preview {
    PlayerView(engine: AudioEngine())
}

import SwiftUI
import UniformTypeIdentifiers

/// 8-bit arcade title screen shown after the splash. Picking a song leads to the player.
///
/// All sizes derive from one pixel unit computed from the screen size,
/// so the layout scales across every iPhone width and height.
struct WelcomeView: View {
    let engine: AudioEngine
    let onTrackLoaded: () -> Void

    @State private var isImporterPresented = false
    @State private var isLoading = false
    @Environment(\.displayScale) private var displayScale

    private typealias Palette = RetroTheme.Arcade

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            // Base pixel: ~2 pt on a 393×852 screen, scaled for other sizes.
            let unit = PixelText.snappedDown(min(size.width / 196, size.height / 380), scale: displayScale)
            let logoPixel = ExtrudedPixelLogo.fittingPixel(
                for: Self.logoLines,
                width: size.width - unit * 16,
                height: size.height * 0.24,
                scale: displayScale
            )
            let spriteCell = PixelText.snappedDown(min(size.width * 0.42 / CGFloat(PixelCassetteSprite.columns), size.height * 0.13 / CGFloat(PixelCassetteSprite.rows)), scale: displayScale)

            VStack(spacing: 0) {
                hud(unit: unit)
                    .padding(.top, unit * 4)

                Spacer(minLength: unit * 6)

                ExtrudedPixelLogo(lines: Self.logoLines, pixel: logoPixel)

                Spacer(minLength: unit * 6)

                PixelCassetteSprite(cell: spriteCell)

                Spacer(minLength: unit * 6)

                stats(unit: unit)

                Spacer(minLength: unit * 8)

                prompt(unit: unit)
                    .padding(.bottom, unit * 5)

                Button {
                    isImporterPresented = true
                } label: {
                    HStack(spacing: unit * 3) {
                        BlinkingPixelText(text: "▶", pixel: unit * 1.5, interval: 0.4)
                        PixelText("Выбрать песню", pixel: unit * 1.5)
                    }
                    .foregroundStyle(Palette.white)
                    .pixelShadow(.black.opacity(0.55), offset: unit)
                }
                .buttonStyle(ArcadeButtonStyle(pixel: unit * 1.5))
                .disabled(isLoading)
                .accessibilityLabel("Выбрать песню")

                footer(unit: unit)
                    .padding(.top, unit * 7)
                    .padding(.bottom, unit * 3)
            }
            .padding(.horizontal, unit * 8)
            .frame(width: size.width, height: size.height)
        }
        .background {
            ZStack {
                Palette.background
                PixelStarfield(unit: PixelText.snapped(2, scale: displayScale))
            }
            .ignoresSafeArea()
        }
        .fileImporter(isPresented: $isImporterPresented, allowedContentTypes: [.audio]) { result in
            guard case .success(let url) = result else { return }
            isLoading = true
            Task {
                await engine.importTrack(from: url)
                isLoading = false
                if engine.isLoaded {
                    onTrackLoaded()
                }
            }
        }
        .alert("Tape Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(engine.errorMessage ?? "")
        }
    }

    private static let logoLines = ["SLOWED", "+REVERB"]

    // MARK: Sections

    /// Top HUD row, like "1UP / HIGH SCORE / 2UP" on arcade cabinets.
    private func hud(unit: CGFloat) -> some View {
        HStack(alignment: .top) {
            hudItem("Side", "A", valueColor: Palette.blue, unit: unit)
            Spacer(minLength: unit * 4)
            hudItem("Hi-Fi", "100%", valueColor: Palette.red, unit: unit)
            Spacer(minLength: unit * 4)
            hudItem("Tape", "01", valueColor: Palette.blue, unit: unit)
        }
    }

    private func hudItem(_ title: String, _ value: String, valueColor: Color, unit: CGFloat) -> some View {
        HStack(spacing: unit * 3) {
            PixelText(title, pixel: unit).foregroundStyle(Palette.white)
            PixelText(value, pixel: unit).foregroundStyle(valueColor)
        }
    }

    /// Middle row, like "RANK / NEW HIGH SCORE / NAME".
    private func stats(unit: CGFloat) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: unit * 4) {
                PixelText("Speed", pixel: unit * 1.25).foregroundStyle(Palette.white)
                PixelText("0.5-1.5x", pixel: unit * 1.25).foregroundStyle(Palette.blue)
            }
            Spacer(minLength: unit * 3)
            VStack(spacing: unit * 4) {
                PixelText("New mix", pixel: unit * 1.25).foregroundStyle(Palette.white)
                PixelText("0.80x", pixel: unit * 2.5).foregroundStyle(Palette.red)
            }
            Spacer(minLength: unit * 3)
            VStack(alignment: .trailing, spacing: unit * 4) {
                PixelText("Reverb", pixel: unit * 1.25).foregroundStyle(Palette.white)
                PixelText("0-100%", pixel: unit * 1.25).foregroundStyle(Palette.blue)
            }
        }
    }

    @ViewBuilder
    private func prompt(unit: CGFloat) -> some View {
        if isLoading {
            LoadingPixelText(pixel: unit)
                .foregroundStyle(Palette.yellow)
        } else {
            BlinkingPixelText(text: "Insert a song to start", pixel: unit)
                .foregroundStyle(Palette.yellow)
        }
    }

    private func footer(unit: CGFloat) -> some View {
        HStack {
            PixelText("© 2026 Slowed Tapes", pixel: unit * 0.8)
            Spacer(minLength: unit * 4)
            PixelText("Credit 01", pixel: unit * 0.8)
        }
        .foregroundStyle(Palette.blue)
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { engine.errorMessage != nil },
            set: { if !$0 { engine.errorMessage = nil } }
        )
    }
}

/// "LOADING" with dots that step 0…3.
private struct LoadingPixelText: View {
    let pixel: CGFloat

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.3)) { context in
            let dots = Int(context.date.timeIntervalSinceReferenceDate / 0.3) % 4
            // Pad with spaces so the width doesn't jump.
            PixelText("Loading" + String(repeating: ".", count: dots) + String(repeating: " ", count: 3 - dots), pixel: pixel)
        }
    }
}

#Preview {
    WelcomeView(engine: AudioEngine(), onTrackLoaded: {})
}

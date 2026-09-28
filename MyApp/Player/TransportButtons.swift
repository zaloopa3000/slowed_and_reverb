import SwiftUI

/// Tape-deck transport block laid out like the reference:
/// wide Play key, stacked ▶▶ / ◀◀, tall Stop — all in a dark recessed housing.
struct TransportButtons: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let onPlayPause: () -> Void
    let onForward: () -> Void
    let onRewind: () -> Void
    let onStop: () -> Void
    /// Held ◀◀ / ▶▶: -1 / +1 to start winding, 0 to stop.
    let onWind: (Int) -> Void
    /// Total block height; the parent scales it with the screen height.
    var height: CGFloat = 118
    /// Draw the block's own recessed housing; off when it sits inside another panel.
    var showsHousing = true

    @Environment(\.pixelUnit) private var unit
    @Environment(\.displayScale) private var displayScale

    /// Pending "is this a hold?" check for ◀◀ / ▶▶.
    @State private var holdTask: Task<Void, Never>?
    /// Set once a press turned into winding, so the release doesn't also skip 10 s.
    @State private var didWind = false

    /// How long ◀◀ / ▶▶ must be held before fast winding starts.
    private static let holdDelay: Duration = .milliseconds(350)

    var body: some View {
        let spacing = height * 0.076
        HStack(spacing: spacing) {
            Button(action: onPlayPause) {
                key(isPlaying ? "⏸" : "▶", label: isPlaying ? "Pause" : "Play", scale: 2.2)
            }
            // Play latches down while the tape is running, like a real deck.
            .buttonStyle(PhysicalKeyStyle(cornerRadius: 14, isLatched: isPlaying))
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            // Tap: ±10 s. Hold: fast wind until released.
            VStack(spacing: spacing) {
                Button { tapped(onForward) } label: { key("▶▶", label: "FF", scale: 0.8) }
                    .buttonStyle(PhysicalKeyStyle(cornerRadius: 12, thickness: 4) { pressed in
                        windKeyPressChanged(pressed, direction: 1)
                    })
                    .accessibilityLabel("Forward 10 seconds")
                    .accessibilityHint("Hold to fast-forward")

                Button { tapped(onRewind) } label: { key("◀◀", label: "Rew", scale: 0.8) }
                    .buttonStyle(PhysicalKeyStyle(cornerRadius: 12, thickness: 4) { pressed in
                        windKeyPressChanged(pressed, direction: -1)
                    })
                    .accessibilityLabel("Back 10 seconds")
                    .accessibilityHint("Hold to rewind")
            }
            .frame(width: height * 0.78)

            Button(action: onStop) { key("■", label: "Stop", scale: 1.6) }
                .buttonStyle(PhysicalKeyStyle(cornerRadius: 14))
                .frame(width: height * 0.6)
                .accessibilityLabel("Stop")
        }
        .padding(showsHousing ? spacing * 1.2 : 0)
        .frame(height: height)
        .background { if showsHousing { housing } }
        .disabled(!isEnabled)
    }

    // MARK: Press-and-hold winding

    private func windKeyPressChanged(_ isPressed: Bool, direction: Int) {
        holdTask?.cancel()
        if isPressed {
            didWind = false
            holdTask = Task {
                try? await Task.sleep(for: Self.holdDelay)
                guard !Task.isCancelled else { return }
                didWind = true
                onWind(direction)
            }
        } else {
            // Always stop on release; stopping when not winding is a no-op.
            onWind(0)
        }
    }

    /// Button action for ◀◀ / ▶▶ — skips only if the press didn't become a wind.
    private func tapped(_ skip: () -> Void) {
        if didWind {
            didWind = false
        } else {
            skip()
        }
    }

    /// Pixel icon with a tiny printed label underneath, like the legends on a tape deck.
    private func key(_ glyph: String, label: String, scale: CGFloat) -> some View {
        let labelPixel = PixelText.snapped(unit * 0.5, scale: displayScale)
        return VStack(spacing: labelPixel * 5) {
            PixelText(glyph, pixel: unit * scale)
            PixelText(label, pixel: labelPixel)
                .opacity(0.7)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var housing: some View {
        let shape = RoundedRectangle(cornerRadius: 22, style: .continuous)
        return shape
            .fill(RetroTheme.plasticDark)
            // Inner shadow: the housing is sunk into the metal body.
            .overlay {
                shape
                    .stroke(Color.black, lineWidth: 10)
                    .blur(radius: 6)
                    .offset(y: 3)
                    .clipShape(shape)
            }
            // Machined edge of the metal around the opening.
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.black.opacity(0.7), .white.opacity(0.25)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.5
                )
            }
    }
}

#Preview {
    VStack(spacing: 24) {
        TransportButtons(isPlaying: false, isEnabled: true, onPlayPause: {}, onForward: {}, onRewind: {}, onStop: {}, onWind: { _ in }, height: 104)
        TransportButtons(isPlaying: true, isEnabled: true, onPlayPause: {}, onForward: {}, onRewind: {}, onStop: {}, onWind: { _ in }, height: 92, showsHousing: false)
    }
    .playerPreview()
}

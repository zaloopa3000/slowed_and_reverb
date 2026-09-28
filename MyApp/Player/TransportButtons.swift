import SwiftUI

/// Tape-deck transport block: wide Play key, stacked ▶▶ / ◀◀, tall Stop — all in a dark
/// recessed housing. Tapping ▶▶ / ◀◀ skips 10 s; holding it winds the tape.
struct TransportButtons: View {
    let isPlaying: Bool
    let isEnabled: Bool
    let onPlayPause: () -> Void
    let onForward: () -> Void
    let onRewind: () -> Void
    let onStop: () -> Void
    /// Called with 1 / -1 when a wind key is held, and 0 when it's released.
    let onWind: (Int) -> Void
    let height: CGFloat

    var body: some View {
        let gap = height * 0.08
        let padding = height * 0.1

        HStack(spacing: gap) {
            Button(action: onPlayPause) {
                glyph(isPlaying ? "pause.fill" : "play.fill", size: height * 0.26)
                    .contentTransition(.symbolEffect(.replace))
            }
            // Play latches down while the tape is running, like a real deck.
            .buttonStyle(PhysicalKeyStyle(cornerRadius: 14, isLatched: isPlaying))
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            VStack(spacing: gap) {
                WindKey(
                    symbol: "forward.fill",
                    glyphSize: height * 0.15,
                    direction: 1,
                    onTap: onForward,
                    onWind: onWind
                )
                .accessibilityLabel("Forward 10 seconds")
                .accessibilityHint("Hold to fast-forward")

                WindKey(
                    symbol: "backward.fill",
                    glyphSize: height * 0.15,
                    direction: -1,
                    onTap: onRewind,
                    onWind: onWind
                )
                .accessibilityLabel("Back 10 seconds")
                .accessibilityHint("Hold to rewind")
            }
            .frame(width: height * 0.8)

            Button(action: onStop) { glyph("stop.fill", size: height * 0.19) }
                .buttonStyle(PhysicalKeyStyle(cornerRadius: 14))
                .frame(width: height * 0.6)
                .accessibilityLabel("Stop")
        }
        .padding(padding)
        .frame(height: height)
        .background { housing }
        .disabled(!isEnabled)
    }

    private func glyph(_ name: String, size: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .semibold))
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

/// ▶▶ / ◀◀ key: a tap skips, a hold winds until release (the key stays latched meanwhile).
///
/// The button's tap and the drag's end both arrive on release, in either order,
/// so a small state machine makes sure a hold never also counts as a tap.
private struct WindKey: View {
    let symbol: String
    let glyphSize: CGFloat
    let direction: Int
    let onTap: () -> Void
    let onWind: (Int) -> Void

    private enum PressState {
        case idle
        /// Held long enough: the tape is winding.
        case winding
        /// Winding just stopped; swallow the release's tap.
        case wound
    }

    @State private var state = PressState.idle

    private static let holdDuration = 0.35

    var body: some View {
        Button {
            switch state {
            case .idle: onTap()
            case .winding: finishWinding()
            case .wound: state = .idle
            }
        } label: {
            Image(systemName: symbol)
                .font(.system(size: glyphSize, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(PhysicalKeyStyle(cornerRadius: 12, thickness: 4, isLatched: state == .winding))
        .simultaneousGesture(
            LongPressGesture(minimumDuration: Self.holdDuration)
                .onEnded { _ in
                    state = .winding
                    onWind(direction)
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    // A new press after a hold whose tap never arrived (finger slid off).
                    if state == .wound { state = .idle }
                }
                .onEnded { _ in
                    switch state {
                    case .idle: break
                    case .winding: finishWinding()
                    case .wound: state = .idle
                    }
                }
        )
    }

    private func finishWinding() {
        onWind(0)
        state = .wound
    }
}

#Preview {
    TransportButtons(
        isPlaying: true,
        isEnabled: true,
        onPlayPause: {},
        onForward: {},
        onRewind: {},
        onStop: {},
        onWind: { _ in },
        height: 118
    )
    .playerPreview()
}

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

    var body: some View {
        HStack(spacing: 9) {
            Button(action: onPlayPause) {
                glyph(isPlaying ? "pause.fill" : "play.fill", size: 30)
                    .contentTransition(.symbolEffect(.replace))
            }
            // Play latches down while the tape is running, like a real deck.
            .buttonStyle(PhysicalKeyStyle(cornerRadius: 14, isLatched: isPlaying))
            .accessibilityLabel(isPlaying ? "Pause" : "Play")

            VStack(spacing: 9) {
                Button(action: onForward) { glyph("forward.fill", size: 17) }
                    .buttonStyle(PhysicalKeyStyle(cornerRadius: 12, thickness: 4))
                    .accessibilityLabel("Forward 10 seconds")

                Button(action: onRewind) { glyph("backward.fill", size: 17) }
                    .buttonStyle(PhysicalKeyStyle(cornerRadius: 12, thickness: 4))
                    .accessibilityLabel("Back 10 seconds")
            }
            .frame(width: 92)

            Button(action: onStop) { glyph("stop.fill", size: 22) }
                .buttonStyle(PhysicalKeyStyle(cornerRadius: 14))
                .frame(width: 70)
                .accessibilityLabel("Stop")
        }
        .padding(11)
        .frame(height: 118)
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

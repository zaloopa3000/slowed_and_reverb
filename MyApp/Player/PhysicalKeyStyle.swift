import SwiftUI

/// A chunky plastic key that physically sinks into its housing when pressed.
///
/// The key is built from three layers:
/// - the *well*: a dark gap around the key, fixed to the housing;
/// - the *side wall*: a darker slab visible below the key face while it's raised;
/// - the *face*: moves down by `thickness` when pressed, covering the side wall,
///   darkens slightly and gets an inner shadow along its top edge.
struct PhysicalKeyStyle: ButtonStyle {
    var cornerRadius: CGFloat = 12
    /// How far the key travels, in points.
    var thickness: CGFloat = 5
    /// Keeps the key partly depressed, like a latched tape-deck Play key.
    var isLatched = false
    var capColor: Color = RetroTheme.plastic

    func makeBody(configuration: Configuration) -> some View {
        PhysicalKey(
            configuration: configuration,
            cornerRadius: cornerRadius,
            thickness: thickness,
            isLatched: isLatched,
            capColor: capColor
        )
    }
}

private struct PhysicalKey: View {
    let configuration: ButtonStyleConfiguration
    let cornerRadius: CGFloat
    let thickness: CGFloat
    let isLatched: Bool
    let capColor: Color

    @Environment(\.isEnabled) private var isEnabled

    /// 0 = fully raised, 1 = bottomed out.
    private var depth: CGFloat {
        if configuration.isPressed { return 1 }
        return isLatched ? 0.6 : 0
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

        configuration.label
            .foregroundStyle(
                LinearGradient(
                    colors: [Color(white: 0.86), Color(white: 0.66)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Dark lip under the glyph reads as a moulded, raised symbol.
            .shadow(color: .black.opacity(0.8), radius: 0.5, y: 1)
            .opacity(isEnabled ? 1 : 0.35)
            .background { face(shape) }
            .brightness(-0.12 * depth)
            .scaleEffect(1 - 0.02 * depth)
            .offset(y: depth * thickness)
            .padding(.bottom, thickness)
            // Side wall of the key, exposed while the face is raised.
            .background {
                shape.fill(
                    LinearGradient(
                        colors: [capColor.mix(with: .black, by: 0.45), capColor.mix(with: .black, by: 0.7)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            // The well in the housing that the key sits in.
            .background {
                shape
                    .fill(Color.black.opacity(0.85))
                    .padding(-2.5)
            }
            .contentShape(shape)
            .animation(.spring(response: 0.13, dampingFraction: 0.55), value: depth)
            // Heavy "thunk" on press, light "click" on release.
            .sensoryFeedback(trigger: configuration.isPressed) { _, isPressed in
                isPressed
                    ? .impact(weight: .heavy, intensity: 0.9)
                    : .impact(weight: .light, intensity: 0.5)
            }
    }

    private func face(_ shape: RoundedRectangle) -> some View {
        shape
            .fill(
                LinearGradient(
                    colors: [
                        capColor.mix(with: .white, by: 0.1),
                        capColor,
                        capColor.mix(with: .black, by: 0.2)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            // Light catching the rounded rim of the key.
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [.white.opacity(0.22), .white.opacity(0.03), .black.opacity(0.45)],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1.2
                )
            }
            // Inner shadow that appears once the key sinks below the housing edge.
            .overlay {
                shape
                    .stroke(Color.black.opacity(0.9), lineWidth: 8)
                    .blur(radius: 5)
                    .offset(y: 3)
                    .clipShape(shape)
                    .opacity(depth)
            }
    }
}

#Preview {
    HStack(spacing: 16) {
        Button {} label: {
            Image(systemName: "play.fill")
                .font(.system(size: 28))
                .frame(width: 140, height: 90)
        }
        .buttonStyle(PhysicalKeyStyle(cornerRadius: 14))

        Button {} label: {
            Image(systemName: "stop.fill")
                .font(.system(size: 22))
                .frame(width: 70, height: 90)
        }
        .buttonStyle(PhysicalKeyStyle(cornerRadius: 14, isLatched: true))
    }
    .padding(30)
    .background(RetroTheme.plasticDark)
}

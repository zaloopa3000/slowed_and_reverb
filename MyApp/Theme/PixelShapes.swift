import SwiftUI

/// Rectangle with stepped ("pixel-rounded") corners, like 8-bit UI boxes.
struct PixelNotchedRect: Shape {
    /// Size of one corner step in points.
    var step: CGFloat = 3
    /// Number of steps per corner.
    var steps = 1

    func path(in rect: CGRect) -> Path {
        let s = step
        var path = Path()
        // Walk the outline clockwise, cutting each corner into a staircase.
        path.move(to: CGPoint(x: rect.minX + s * CGFloat(steps), y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - s * CGFloat(steps), y: rect.minY))
        for i in 0..<steps {
            let base = CGFloat(steps - i)
            path.addLine(to: CGPoint(x: rect.maxX - s * (base - 1), y: rect.minY + s * CGFloat(i)))
            path.addLine(to: CGPoint(x: rect.maxX - s * (base - 1), y: rect.minY + s * CGFloat(i + 1)))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - s * CGFloat(steps)))
        for i in 0..<steps {
            let base = CGFloat(i + 1)
            path.addLine(to: CGPoint(x: rect.maxX - s * CGFloat(i), y: rect.maxY - s * (CGFloat(steps) - base)))
            path.addLine(to: CGPoint(x: rect.maxX - s * base, y: rect.maxY - s * (CGFloat(steps) - base)))
        }
        path.addLine(to: CGPoint(x: rect.minX + s * CGFloat(steps), y: rect.maxY))
        for i in 0..<steps {
            let base = CGFloat(steps - i)
            path.addLine(to: CGPoint(x: rect.minX + s * (base - 1), y: rect.maxY - s * CGFloat(i)))
            path.addLine(to: CGPoint(x: rect.minX + s * (base - 1), y: rect.maxY - s * CGFloat(i + 1)))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + s * CGFloat(steps)))
        for i in 0..<steps {
            let base = CGFloat(i + 1)
            path.addLine(to: CGPoint(x: rect.minX + s * CGFloat(i), y: rect.minY + s * (CGFloat(steps) - base)))
            path.addLine(to: CGPoint(x: rect.minX + s * base, y: rect.minY + s * (CGFloat(steps) - base)))
        }
        path.closeSubpath()
        return path
    }
}

/// Fine checkerboard used for 8-bit dithering.
struct DitherPattern: Shape {
    var cell: CGFloat = 2

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let columns = Int((rect.width / cell).rounded(.up))
        let rows = Int((rect.height / cell).rounded(.up))
        for row in 0..<rows {
            for column in 0..<columns where (row + column).isMultiple(of: 2) {
                path.addRect(CGRect(
                    x: rect.minX + CGFloat(column) * cell,
                    y: rect.minY + CGFloat(row) * cell,
                    width: cell,
                    height: cell
                ))
            }
        }
        return path
    }
}

/// Chunky 8-bit button: a solid "base" block under the face that the face
/// drops onto when pressed (no blur — hard pixel edges only).
struct ArcadeButtonStyle: ButtonStyle {
    var pixel: CGFloat = 3
    var face: Color = RetroTheme.Arcade.red
    var highlight: Color = Color(red: 1.0, green: 0.62, blue: 0.52)
    var base: Color = Color(red: 0.45, green: 0.12, blue: 0.2)

    func makeBody(configuration: Configuration) -> some View {
        let depth = pixel * 2
        let pressed = configuration.isPressed
        let shape = PixelNotchedRect(step: pixel, steps: 2)

        configuration.label
            .padding(.horizontal, pixel * 8)
            .padding(.vertical, pixel * 5)
            .frame(maxWidth: .infinity)
            .background {
                shape.fill(face)
                    // Light band along the top edge.
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(highlight)
                            .frame(height: pixel)
                            .padding(.horizontal, pixel * 2)
                            .padding(.top, pixel)
                    }
                    // Dithered shade along the bottom edge.
                    .overlay(alignment: .bottom) {
                        DitherPattern(cell: pixel)
                            .fill(base.opacity(0.55))
                            .frame(height: pixel * 2)
                            .padding(.horizontal, pixel * 2)
                            .padding(.bottom, pixel)
                    }
                    .overlay { shape.stroke(Color.black, lineWidth: pixel) }
            }
            .offset(y: pressed ? depth : 0)
            .padding(.bottom, depth)
            .background(alignment: .bottom) {
                shape.fill(base)
                    .overlay { shape.stroke(Color.black, lineWidth: pixel) }
            }
            // Instant, un-eased motion: 8-bit things don't tween.
            .animation(nil, value: pressed)
            .sensoryFeedback(trigger: pressed) { _, isPressed in
                isPressed ? .impact(weight: .heavy, intensity: 0.9) : .impact(weight: .light, intensity: 0.5)
            }
    }
}

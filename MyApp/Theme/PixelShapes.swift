import SwiftUI

/// Rectangle with stepped ("pixel-rounded") corners, like 8-bit UI boxes.
struct PixelNotchedRect: Shape {
    /// Size of one corner step in points.
    var step: CGFloat = 3
    /// Number of steps per corner.
    var steps = 1

    func path(in rect: CGRect) -> Path {
        let s = step
        let n = CGFloat(steps)
        var path = Path()

        // Walk the outline clockwise; each corner is a staircase of `steps` steps.
        path.move(to: CGPoint(x: rect.minX + n * s, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - n * s, y: rect.minY))
        for k in 1...steps { // top-right: down, then right
            let k = CGFloat(k)
            path.addLine(to: CGPoint(x: rect.maxX - (n - k + 1) * s, y: rect.minY + k * s))
            path.addLine(to: CGPoint(x: rect.maxX - (n - k) * s, y: rect.minY + k * s))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - n * s))
        for k in 1...steps { // bottom-right: left, then down
            let k = CGFloat(k)
            path.addLine(to: CGPoint(x: rect.maxX - k * s, y: rect.maxY - (n - k + 1) * s))
            path.addLine(to: CGPoint(x: rect.maxX - k * s, y: rect.maxY - (n - k) * s))
        }
        path.addLine(to: CGPoint(x: rect.minX + n * s, y: rect.maxY))
        for k in 1...steps { // bottom-left: up, then left
            let k = CGFloat(k)
            path.addLine(to: CGPoint(x: rect.minX + (n - k + 1) * s, y: rect.maxY - k * s))
            path.addLine(to: CGPoint(x: rect.minX + (n - k) * s, y: rect.maxY - k * s))
        }
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + n * s))
        for k in 1...steps { // top-left: right, then up
            let k = CGFloat(k)
            path.addLine(to: CGPoint(x: rect.minX + k * s, y: rect.minY + (n - k + 1) * s))
            path.addLine(to: CGPoint(x: rect.minX + k * s, y: rect.minY + (n - k) * s))
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

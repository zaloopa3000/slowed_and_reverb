import SwiftUI
import UIKit

/// Shown over the GIF while a tape is being recorded (exported):
/// blinking "● REC", a segmented progress bar and the percentage.
struct RecordingOverlay: View {
    let progress: Double

    @Environment(\.pixelUnit) private var unit
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        ZStack {
            Color.black.opacity(0.62)
            Scanlines().opacity(0.3)

            VStack(spacing: unit * 5) {
                HStack(spacing: unit * 3) {
                    BlinkingPixelText(text: "●", pixel: unit * 1.5, interval: 0.5)
                        .foregroundStyle(RetroTheme.accentRed)
                        .lcdGlow(RetroTheme.accentRed, radius: 5)
                    PixelText("Rec", pixel: unit * 1.5)
                        .foregroundStyle(RetroTheme.accentRed)
                        .lcdGlow(RetroTheme.accentRed, radius: 5)
                }

                PixelText("Recording tape", pixel: unit * 0.8)
                    .foregroundStyle(RetroTheme.text.opacity(0.8))

                progressBar
                    .frame(height: unit * 4)
                    .padding(.horizontal, unit * 12)

                PixelText("\(Int((progress * 100).rounded(.down)))%", pixel: unit)
                    .foregroundStyle(RetroTheme.lcdText)
                    .lcdGlow()

                PixelText("Tap Rec to cancel", pixel: unit * 0.5)
                    .foregroundStyle(RetroTheme.text.opacity(0.5))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Recording tape")
        .accessibilityValue("\(Int(progress * 100)) percent")
    }

    private var progressBar: some View {
        Canvas { context, size in
            let block = PixelText.snapped(unit * 2, scale: displayScale)
            let gap = PixelText.snapped(unit, scale: displayScale)
            let count = max(Int((size.width + gap) / (block + gap)), 1)
            let lit = Int((progress * Double(count)).rounded(.down))
            for index in 0..<count {
                let rect = CGRect(x: CGFloat(index) * (block + gap), y: 0, width: block, height: size.height)
                let color = index < lit ? RetroTheme.accentRed : RetroTheme.neonViolet.opacity(0.18)
                context.fill(Path(rect), with: .color(color))
            }
        }
        .shadow(color: RetroTheme.accentRed.opacity(0.6), radius: 4)
    }
}

/// System share sheet (Files, AirDrop, messengers…) for an exported file.
struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    let onFinish: () -> Void

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        controller.completionWithItemsHandler = { _, _, _, _ in onFinish() }
        return controller
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

#Preview {
    RecordingOverlay(progress: 0.42)
        .frame(height: 300)
        .playerPreview()
}

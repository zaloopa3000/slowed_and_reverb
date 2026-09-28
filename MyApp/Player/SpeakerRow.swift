import SwiftUI

/// Row under the GIF: stereo L/R meter, status LED and round EJECT / REC keys.
struct SpeakerRow: View {
    let meter: LevelMeter
    let isPlaying: Bool
    let canRecord: Bool
    var isRecording = false
    let onEject: () -> Void
    let onRecord: () -> Void
    let height: CGFloat

    @Environment(\.pixelUnit) private var unit

    var body: some View {
        // Keys shrink with the row on short screens.
        let keySize = min(height * 0.62, unit * 24)

        HStack(spacing: unit * 5) {
            StereoMeterView(meter: meter, isPlaying: isPlaying)

            VStack(spacing: unit * 3) {
                StatusLED(isOn: isPlaying || isRecording, size: unit * 5)

                HStack(spacing: unit * 4) {
                    roundKey(symbol: "eject.fill", title: "Eject", size: keySize, action: onEject)
                        .accessibilityLabel("Eject")
                        .accessibilityHint("Load another track")

                    roundKey(symbol: "record.circle", title: "Rec", size: keySize, isLit: isRecording, action: onRecord)
                        .disabled(!canRecord && !isRecording)
                        .accessibilityLabel(isRecording ? "Stop recording" : "Record")
                        .accessibilityHint(isRecording ? "" : "Save the slowed track as a file")
                }
            }
        }
        .frame(height: height)
    }

    private func roundKey(
        symbol: String,
        title: String,
        size: CGFloat,
        isLit: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            let label = VStack(spacing: unit) {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.3, weight: .bold))
                PixelText(title, pixel: unit * 0.6)
            }
            .frame(width: size, height: size)

            // A lit REC key glows pink while recording.
            if isLit {
                label
                    .foregroundStyle(RetroTheme.accentRed)
                    .lcdGlow(RetroTheme.accentRed, radius: 4)
            } else {
                label
            }
        }
        .buttonStyle(PhysicalKeyStyle(cornerRadius: size / 2, thickness: 3.5, isLatched: isLit))
    }
}

/// Small pink LED that glows while playing or recording.
struct StatusLED: View {
    let isOn: Bool
    var size: CGFloat = 10

    var body: some View {
        Circle()
            .fill(isOn ? RetroTheme.accentRed : RetroTheme.accentRed.mix(with: .black, by: 0.65))
            .frame(width: size, height: size)
            .overlay(alignment: .topLeading) {
                // Specular highlight on the LED dome.
                Circle()
                    .fill(Color.white.opacity(isOn ? 0.75 : 0.25))
                    .frame(width: size * 0.3, height: size * 0.3)
                    .offset(x: size * 0.2, y: size * 0.2)
            }
            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
            .shadow(color: RetroTheme.accentRed.opacity(isOn ? 0.9 : 0), radius: size * 0.6)
            .shadow(color: RetroTheme.accentRed.opacity(isOn ? 0.5 : 0), radius: size * 1.4)
            .animation(.easeInOut(duration: 0.25), value: isOn)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        SpeakerRow(meter: LevelMeter(), isPlaying: false, canRecord: true, onEject: {}, onRecord: {}, height: 86)
        SpeakerRow(meter: LevelMeter(), isPlaying: true, canRecord: true, isRecording: true, onEject: {}, onRecord: {}, height: 86)
    }
    .playerPreview()
}

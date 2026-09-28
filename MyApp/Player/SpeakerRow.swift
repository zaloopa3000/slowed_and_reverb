import SwiftUI

/// Row under the GIF: compact L/R level meter, status LED and the EJECT / REC keys side by side.
struct SpeakerRow: View {
    let meter: LevelMeter
    let isPlaying: Bool
    let canRecord: Bool
    /// REC stays latched down while a tape is being recorded.
    var isRecording = false
    let onEject: () -> Void
    let onRecord: () -> Void
    /// Row height; the parent scales it with the screen height.
    var height: CGFloat = 86

    @Environment(\.pixelUnit) private var unit
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let keySpacing: CGFloat = 8
        let keyHeight = height

        HStack(spacing: 12) {
            StereoMeterView(meter: meter, isPlaying: isPlaying)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            StatusLED(isOn: isPlaying)

            HStack(spacing: keySpacing) {
                roundKey(glyph: "⏏", title: "Eject", height: keyHeight, action: onEject)
                    .disabled(isRecording)
                roundKey(glyph: "●", title: "Rec", height: keyHeight, isLatched: isRecording, glyphColor: isRecording ? RetroTheme.accentRed : nil, action: onRecord)
                    .disabled(!canRecord)
                    .accessibilityHint(isRecording ? "Cancels recording" : "Records the track with the current speed and reverb")
            }
        }
        .frame(height: height)
    }

    private func roundKey(
        glyph: String,
        title: String,
        height: CGFloat,
        isLatched: Bool = false,
        glyphColor: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let labelPixel = PixelText.snapped(unit * 0.5, scale: displayScale)
        return Button(action: action) {
            VStack(spacing: labelPixel * 2) {
                if let glyphColor {
                    PixelText(glyph, pixel: labelPixel * 1.5)
                        .foregroundStyle(glyphColor)
                        .lcdGlow(glyphColor, radius: 4)
                } else {
                    PixelText(glyph, pixel: labelPixel * 1.5)
                }
                PixelText(title, pixel: labelPixel)
            }
            // The key's travel (thickness) is added below the face by the style.
            .frame(width: 46, height: max(height - 3.5, 24))
        }
        .buttonStyle(PhysicalKeyStyle(cornerRadius: 12, thickness: 3.5, isLatched: isLatched))
        .accessibilityLabel(title)
    }
}

/// Small red LED that glows while playing.
struct StatusLED: View {
    let isOn: Bool

    var body: some View {
        Circle()
            .fill(isOn ? RetroTheme.accentRed : RetroTheme.accentRed.mix(with: .black, by: 0.65))
            .frame(width: 10, height: 10)
            .overlay(alignment: .topLeading) {
                // Specular highlight on the LED dome.
                Circle()
                    .fill(Color.white.opacity(isOn ? 0.75 : 0.25))
                    .frame(width: 3, height: 3)
                    .offset(x: 2, y: 2)
            }
            .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
            .shadow(color: RetroTheme.accentRed.opacity(isOn ? 0.9 : 0), radius: 6)
            .shadow(color: RetroTheme.accentRed.opacity(isOn ? 0.5 : 0), radius: 14)
            .animation(.easeInOut(duration: 0.25), value: isOn)
            .accessibilityHidden(true)
    }
}

#Preview {
    VStack(spacing: 24) {
        SpeakerRow(meter: LevelMeter(), isPlaying: false, canRecord: true, onEject: {}, onRecord: {}, height: 48)
        SpeakerRow(meter: LevelMeter(), isPlaying: true, canRecord: true, isRecording: true, onEject: {}, onRecord: {}, height: 48)
    }
    .playerPreview()
}

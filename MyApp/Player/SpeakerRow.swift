import SwiftUI

/// Speaker grille slice + status LED + round EJECT / REC keys
/// (in the spot where the reference has VOL+ / VOL−).
struct SpeakerRow: View {
    let isPlaying: Bool
    let canRecord: Bool
    let onEject: () -> Void
    let onRecord: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(.speakerGrille)
                .resizable()
                .scaledToFill()
                .frame(height: 30)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()

            StatusLED(isOn: isPlaying)

            roundKey(symbol: "eject.fill", title: "Eject", action: onEject)
            roundKey(symbol: "record.circle", title: "Rec", action: onRecord)
                .disabled(!canRecord)
        }
        .frame(height: 50)
    }

    private func roundKey(symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(RetroTheme.pixel(7, weight: .bold))
                    .textCase(.uppercase)
            }
            .frame(width: 44, height: 40)
        }
        .buttonStyle(PhysicalKeyStyle(cornerRadius: 22, thickness: 3.5))
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

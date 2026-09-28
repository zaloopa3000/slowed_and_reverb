import AVFoundation

// iOS 26 / 27 compatibility wrappers (see the table in CLAUDE.md).
// Always call these instead of the underlying AVFAudio APIs.

nonisolated extension AVAudioEngine {
    /// `connectNode` on iOS 27 (where `connect` is deprecated), `connect` before.
    func connectCompat(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat) throws {
        if #available(iOS 27, *) {
            try connectNode(source, to: destination, format: format)
        } else {
            connect(source, to: destination, format: format)
        }
    }
}

nonisolated extension AVAudioPlayerNode {
    /// `playAudio()` on iOS 27 (where `play()` is deprecated), `play()` before.
    func playCompat() throws {
        if #available(iOS 27, *) {
            try playAudio()
        } else {
            play()
        }
    }
}

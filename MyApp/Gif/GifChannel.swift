import Foundation
import Observation

/// The LCD "TV": which GIF is on, and switching channels.
@Observable
final class GifChannel {
    enum State {
        case idle
        /// Loading the next GIF — the screen shows static.
        case tuning
        case showing(AnimatedGIF)
        /// Network or decoding failed — static plus "NO SIGNAL".
        case noSignal
    }

    private(set) var state: State = .idle
    /// Channel number shown in the on-screen display; bumps on every switch.
    private(set) var number = 0

    /// The GIF on screen right now, if any.
    var currentGIF: AnimatedGIF? {
        if case .showing(let gif) = state { gif } else { nil }
    }

    @ObservationIgnored private var loadTask: Task<Void, Never>?

    /// Minimum time the static is shown, so switching always feels like a real channel change.
    private static let minimumStatic: Duration = .milliseconds(450)

    /// Tunes in the first GIF when the screen first appears.
    func tuneInIfNeeded() {
        guard case .idle = state else { return }
        nextChannel()
    }

    func nextChannel() {
        loadTask?.cancel()
        number = number % 99 + 1
        state = .tuning

        loadTask = Task { [weak self] in
            async let gif = GiphyService.randomGIF()
            try? await Task.sleep(for: Self.minimumStatic)
            do {
                let loaded = try await gif
                guard !Task.isCancelled else { return }
                self?.state = .showing(loaded)
            } catch {
                guard !Task.isCancelled else { return }
                self?.state = .noSignal
            }
        }
    }
}

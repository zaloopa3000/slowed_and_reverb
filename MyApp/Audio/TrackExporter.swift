import Foundation
import Observation

/// State of "recording" (exporting) the current track, for the REC key and the share sheet.
@Observable
final class TrackExporter {
    /// A finished file ready to share; identity changes on every export so the sheet re-presents.
    struct ExportedFile: Identifiable {
        let id = UUID()
        let url: URL
    }

    private(set) var isRecording = false
    private(set) var progress: Double = 0
    /// Set when an export finishes; drives the share sheet.
    var exported: ExportedFile?
    var errorMessage: String?

    @ObservationIgnored private var task: Task<Void, Never>?

    /// Records an `.mp4` with the track over the looping `gif`; without a GIF, an `.m4a`.
    func start(source: URL, title: String, speed: Float, reverb: Float, gif: AnimatedGIF? = nil) {
        guard !isRecording else { return }
        isRecording = true
        progress = 0
        errorMessage = nil

        task = Task { [weak self] in
            let settings = AudioExporter.Settings(speed: speed, reverb: reverb)
            let report: @Sendable (Double) -> Void = { value in
                Task { @MainActor in self?.progress = value }
            }
            do {
                let url = if let gif {
                    try await VideoExporter.export(source: source, title: title, settings: settings, gif: gif, progress: report)
                } else {
                    try await AudioExporter.export(source: source, title: title, settings: settings, progress: report)
                }
                self?.exported = ExportedFile(url: url)
            } catch is CancellationError {
                // Cancelled from the REC key — nothing to report.
            } catch {
                self?.errorMessage = "Couldn't record this tape."
            }
            self?.isRecording = false
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

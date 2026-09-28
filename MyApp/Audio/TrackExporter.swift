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

    func start(source: URL, title: String, speed: Float, reverb: Float) {
        guard !isRecording else { return }
        isRecording = true
        progress = 0
        errorMessage = nil

        task = Task { [weak self] in
            do {
                let url = try await AudioExporter.export(
                    source: source,
                    title: title,
                    settings: .init(speed: speed, reverb: reverb),
                    progress: { value in
                        Task { @MainActor in self?.progress = value }
                    }
                )
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

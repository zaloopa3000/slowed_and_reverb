import Foundation
import Testing
@testable import MyApp

@Suite("TrackMetadata")
struct TrackMetadataTests {
    @Test func untaggedFileFallsBackToFileName() async throws {
        let url = try TestFixtures.makeAudioFile(name: "My Cool Track")
        let metadata = await TrackMetadata.load(from: url)
        #expect(metadata.title == "My Cool Track")
        #expect(metadata.artist == "Unknown Artist")
    }

    @Test func missingFileFallsBackToFileName() async {
        let url = FileManager.default.temporaryDirectory.appending(path: "Ghost Track.mp3")
        let metadata = await TrackMetadata.load(from: url)
        #expect(metadata == TrackMetadata(title: "Ghost Track", artist: "Unknown Artist"))
    }

    @Test func emptyPlaceholder() {
        #expect(TrackMetadata.empty.title == "No Tape")
        #expect(TrackMetadata.empty.artist == "Insert a track")
    }
}

@Suite("TrackExporter")
struct TrackExporterTests {
    /// Waits (bounded) for the export task to finish.
    private func waitUntilDone(_ exporter: TrackExporter) async throws {
        for _ in 0..<500 where exporter.isRecording {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    @Test func successfulExportPublishesFile() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.3)
        let exporter = TrackExporter()

        exporter.start(source: source, title: "Exporter Test \(UUID().uuidString)", speed: 0.85, reverb: 20)
        #expect(exporter.isRecording)
        try await waitUntilDone(exporter)

        #expect(!exporter.isRecording)
        #expect(exporter.errorMessage == nil)
        let file = try #require(exporter.exported)
        #expect(FileManager.default.fileExists(atPath: file.url.path(percentEncoded: false)))
        try? FileManager.default.removeItem(at: file.url)
    }

    @Test func exportWithGIFPublishesVideo() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.3)
        let gif = try #require(AnimatedGIF(data: try TestFixtures.makeGIFData(delays: [0.1, 0.1]), maxPixelSize: 100))
        let exporter = TrackExporter()

        exporter.start(source: source, title: "Video \(UUID().uuidString)", speed: 0.85, reverb: 20, gif: gif)
        try await waitUntilDone(exporter)

        #expect(exporter.errorMessage == nil)
        let file = try #require(exporter.exported)
        #expect(file.url.pathExtension == "mp4")
        try? FileManager.default.removeItem(at: file.url)
    }

    @Test func failedExportReportsError() async throws {
        let missing = FileManager.default.temporaryDirectory.appending(path: "missing-\(UUID().uuidString).caf")
        let exporter = TrackExporter()

        exporter.start(source: missing, title: "Missing", speed: 1, reverb: 0)
        try await waitUntilDone(exporter)

        #expect(!exporter.isRecording)
        #expect(exporter.exported == nil)
        #expect(exporter.errorMessage == "Couldn't record this tape.")
    }

    @Test func cancelStopsWithoutError() async throws {
        // Long enough that the render is still running when we cancel.
        let source = try TestFixtures.makeAudioFile(duration: 60)
        let exporter = TrackExporter()

        exporter.start(source: source, title: "Cancel \(UUID().uuidString)", speed: 0.8, reverb: 0)
        exporter.cancel()
        try await waitUntilDone(exporter)

        #expect(!exporter.isRecording)
        #expect(exporter.exported == nil)
        #expect(exporter.errorMessage == nil)
    }

    @Test func secondStartWhileRecordingIsIgnored() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.3)
        let exporter = TrackExporter()

        exporter.start(source: source, title: "First \(UUID().uuidString)", speed: 1, reverb: 10)
        // A bogus source would error out if this call weren't ignored.
        exporter.start(source: URL(filePath: "/nonexistent.caf"), title: "Second", speed: 1, reverb: 0)
        try await waitUntilDone(exporter)

        #expect(exporter.errorMessage == nil)
        let file = try #require(exporter.exported)
        #expect(file.url.lastPathComponent.hasPrefix("First"))
        try? FileManager.default.removeItem(at: file.url)
    }
}

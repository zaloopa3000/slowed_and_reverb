import AVFoundation
import Synchronization
import Testing
@testable import MyApp

@Suite("AudioExporter.fileName")
struct AudioExporterFileNameTests {
    private func name(_ title: String, speed: Float = 1, reverb: Float = 0) -> String {
        AudioExporter.fileName(title: title, settings: .init(speed: speed, reverb: reverb))
    }

    @Test func slowedWithReverb() {
        #expect(name("Song", speed: 0.8, reverb: 40) == "Song (slowed + reverb).m4a")
    }

    @Test func spedUp() {
        #expect(name("Song", speed: 1.25) == "Song (sped up).m4a")
    }

    @Test func reverbOnly() {
        #expect(name("Song", reverb: 10) == "Song (reverb).m4a")
    }

    @Test func noEffectsHasNoSuffix() {
        #expect(name("Song") == "Song.m4a")
        // Tiny float drift around 1.0 still counts as normal speed.
        #expect(name("Song", speed: 1.0005) == "Song.m4a")
    }

    @Test func stripsUnsafeCharacters() {
        #expect(name("AC/DC: Back?In*Black") == "AC DC Back In Black.m4a")
        #expect(name("  lots   of \t space  ") == "lots of space.m4a")
    }

    @Test func customExtension() {
        let name = AudioExporter.fileName(title: "Song", settings: .init(speed: 0.8, reverb: 40), fileExtension: "mp4")
        #expect(name == "Song (slowed + reverb).mp4")
    }

    @Test func emptyTitleFallsBackToTape() {
        #expect(name("") == "Tape.m4a")
        #expect(name("///") == "Tape.m4a")
    }
}

/// Thread-safe collector for progress callbacks coming off the main actor.
private final class ProgressLog: Sendable {
    private let storage = Mutex<[Double]>([])

    var values: [Double] { storage.withLock { $0 } }

    func append(_ value: Double) {
        storage.withLock { $0.append(value) }
    }
}

@Suite("AudioExporter.export")
struct AudioExporterExportTests {
    @Test func rendersSlowedFileWithReverbTail() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.5)
        let log = ProgressLog()

        let output = try await AudioExporter.export(
            source: source,
            title: "Export Test \(UUID().uuidString)",
            settings: .init(speed: 0.8, reverb: 30),
            progress: { log.append($0) }
        )
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(output.pathExtension == "m4a")
        #expect(output.lastPathComponent.hasSuffix("(slowed + reverb).m4a"))

        let file = try AVAudioFile(forReading: output)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        // 0.5 s / 0.8 speed + 2.5 s reverb tail = 3.125 s (allow for AAC priming/padding).
        #expect(abs(seconds - 3.125) < 0.2)
        #expect(file.processingFormat.channelCount == 2)

        let progress = log.values
        #expect(progress.last == 1)
        #expect(progress == progress.sorted())
        #expect(progress.allSatisfy { (0...1).contains($0) })
    }

    @Test func cancellationRemovesPartialFile() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.5)
        let title = "Cancel Test \(UUID().uuidString)"
        let settings = AudioExporter.Settings(speed: 0.9, reverb: 0)

        let task = Task {
            // Cancel before rendering starts so the loop's cancellation check fires deterministically.
            withUnsafeCurrentTask { $0?.cancel() }
            return try await AudioExporter.export(source: source, title: title, settings: settings, progress: { _ in })
        }

        await #expect(throws: CancellationError.self) {
            try await task.value
        }

        let expected = FileManager.default.temporaryDirectory
            .appending(path: "Exports", directoryHint: .isDirectory)
            .appending(path: AudioExporter.fileName(title: title, settings: settings))
        #expect(!FileManager.default.fileExists(atPath: expected.path(percentEncoded: false)))
    }

    @Test func writesToExplicitDestination() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.2)
        let destination = FileManager.default.temporaryDirectory.appending(path: "dest-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: destination) }

        let output = try await AudioExporter.export(
            source: source,
            title: "Ignored",
            settings: .init(speed: 1, reverb: 0),
            destination: destination,
            progress: { _ in }
        )
        #expect(output == destination)
        #expect(FileManager.default.fileExists(atPath: destination.path(percentEncoded: false)))
    }

    @Test func missingSourceThrows() async {
        let missing = FileManager.default.temporaryDirectory.appending(path: "does-not-exist-\(UUID().uuidString).caf")
        await #expect(throws: (any Error).self) {
            _ = try await AudioExporter.export(
                source: missing,
                title: "Missing",
                settings: .init(speed: 1, reverb: 0),
                progress: { _ in }
            )
        }
    }
}

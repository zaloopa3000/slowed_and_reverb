import AVFoundation
import Testing
@testable import MyApp

@Suite("AudioEngine")
struct AudioEngineTests {
    @Test func initialState() {
        let engine = AudioEngine()
        #expect(!engine.isLoaded)
        #expect(!engine.isPlaying)
        #expect(engine.metadata == .empty)
        #expect(engine.sourceURL == nil)
        #expect(engine.progress == 0)
        #expect(engine.speed == 1)
        #expect(engine.reverb == 0)
    }

    @Test func transportIsNoOpWithoutTrack() {
        let engine = AudioEngine()
        engine.play()
        engine.seek(to: 10)
        engine.startWinding(1)
        #expect(!engine.isPlaying)
        #expect(engine.currentTime == 0)
        #expect(engine.windDirection == 0)
    }

    @Test func loadsStereoTrack() async throws {
        let url = try TestFixtures.makeAudioFile(name: "Stereo Tone", duration: 1)
        let engine = AudioEngine()
        try await engine.load(url: url)

        #expect(engine.isLoaded)
        #expect(engine.isStereo)
        #expect(!engine.isPlaying)
        #expect(engine.sourceURL == url)
        #expect(abs(engine.duration - 1) < 0.001)
        #expect(engine.currentTime == 0)
        #expect(engine.errorMessage == nil)
        // No embedded tags → title from the file name.
        #expect(engine.metadata.title == "Stereo Tone")
    }

    @Test func loadsMonoTrackAtOtherSampleRate() async throws {
        let url = try TestFixtures.makeAudioFile(duration: 0.5, sampleRate: 48_000, channels: 1)
        let engine = AudioEngine()
        try await engine.load(url: url)

        #expect(engine.isLoaded)
        #expect(!engine.isStereo)
        #expect(abs(engine.duration - 0.5) < 0.001)
    }

    @Test func loadingInvalidFileThrows() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "garbage-\(UUID().uuidString).caf")
        try Data("definitely not audio".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let engine = AudioEngine()
        await #expect(throws: (any Error).self) {
            try await engine.load(url: url)
        }
        #expect(!engine.isLoaded)
    }

    @Test func seekClampsToTrack() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 1))

        engine.seek(to: 0.25)
        #expect(abs(engine.currentTime - 0.25) < 1e-9)
        #expect(abs(engine.progress - 0.25) < 1e-6)

        engine.seek(to: -3)
        #expect(engine.currentTime == 0)

        engine.seek(to: 99)
        #expect(engine.currentTime == engine.duration)
        #expect(engine.progress == 1)
        #expect(!engine.isPlaying)
    }

    @Test func skipMovesRelativeToCurrentTime() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 1))

        engine.seek(to: 0.5)
        engine.skip(by: 0.2)
        #expect(abs(engine.currentTime - 0.7) < 1e-9)
        engine.skip(by: -1)
        #expect(engine.currentTime == 0)
    }

    @Test func stopRewinds() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 1))

        engine.seek(to: 0.6)
        engine.stop()
        #expect(engine.currentTime == 0)
        #expect(!engine.isPlaying)
    }

    @Test func windingStartsAndStops() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 5))

        engine.startWinding(0)
        #expect(engine.windDirection == 0)

        engine.startWinding(1)
        #expect(engine.windDirection == 1)
        engine.stopWinding()
        #expect(engine.windDirection == 0)
    }

    @Test func windingForwardStopsAtEndOfTape() async throws {
        let engine = AudioEngine()
        // Shorter than one wind step, so the first tick reaches the end.
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 0.5))

        engine.startWinding(1)
        for _ in 0..<50 where engine.windDirection != 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(engine.windDirection == 0)
        #expect(engine.currentTime == engine.duration)
    }

    @Test func loadingNewTrackResetsPosition() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 1))
        engine.seek(to: 0.8)

        try await engine.load(url: TestFixtures.makeAudioFile(name: "Second", duration: 2))
        #expect(engine.currentTime == 0)
        #expect(abs(engine.duration - 2) < 0.001)
        #expect(engine.metadata.title == "Second")
    }

    @Test func stopCancelsWinding() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 5))

        engine.startWinding(-1)
        #expect(engine.windDirection == -1)
        engine.stop()
        #expect(engine.windDirection == 0)
        #expect(engine.currentTime == 0)
    }

    @Test func windingRewindStopsAtStart() async throws {
        let engine = AudioEngine()
        try await engine.load(url: TestFixtures.makeAudioFile(duration: 5))
        engine.seek(to: 0.5)

        engine.startWinding(-1)
        for _ in 0..<50 where engine.windDirection != 0 {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(engine.windDirection == 0)
        #expect(engine.currentTime == 0)
    }

    @Test func effectParametersAreStored() {
        let engine = AudioEngine()
        engine.speed = 0.75
        engine.reverb = 55
        #expect(engine.speed == 0.75)
        #expect(engine.reverb == 55)
        #expect(AudioEngine.speedRange.contains(engine.speed))
        #expect(AudioEngine.reverbRange.contains(engine.reverb))
    }
}

import AVFoundation
import Testing
@testable import MyApp

@Suite("VideoExporter helpers")
struct VideoExporterHelperTests {
    @Test func frameTimesStretchWithSlowerRate() {
        let times = VideoExporter.frameEndTimes(delays: [0.1, 0.1, 0.2], rate: 0.5)
        #expect(times.map(\.seconds) == [0.2, 0.4, 0.8])
    }

    @Test func frameTimesAtNormalRate() {
        let times = VideoExporter.frameEndTimes(delays: [0.05, 0.05], rate: 1)
        #expect(times.map(\.seconds) == [0.05, 0.1])
    }

    @Test func loopRangesCoverTotalWithTrimmedTail() {
        let ranges = VideoExporter.loopRanges(
            total: CMTime(seconds: 2.5, preferredTimescale: 600),
            loop: CMTime(seconds: 1, preferredTimescale: 600)
        )
        #expect(ranges.map(\.start.seconds) == [0, 1, 2])
        #expect(ranges.map(\.duration.seconds) == [1, 1, 0.5])
    }

    @Test func loopRangesEmptyForZeroLoop() {
        #expect(VideoExporter.loopRanges(total: CMTime(seconds: 3, preferredTimescale: 600), loop: .zero).isEmpty)
    }

    @Test func videoSizeScalesToMaxSideAndStaysEven() {
        let landscape = VideoExporter.videoSize(width: 480, height: 271)
        #expect(landscape.width == VideoExporter.maxSide)
        #expect(landscape.height % 2 == 0)
        #expect(abs(landscape.height - 406) <= 2)

        let square = VideoExporter.videoSize(width: 8, height: 8)
        #expect(square.width == VideoExporter.maxSide && square.height == VideoExporter.maxSide)
    }
}

@Suite("VideoExporter.export")
struct VideoExporterExportTests {
    @Test func writesVideoWithLoopedGIFAndAudio() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.5)
        let gifData = try TestFixtures.makeGIFData(delays: [0.1, 0.1, 0.1])
        let gif = try #require(AnimatedGIF(data: gifData, maxPixelSize: 100))

        let output = try await VideoExporter.export(
            source: source,
            title: "Video Test \(UUID().uuidString)",
            settings: .init(speed: 0.8, reverb: 30),
            gif: gif,
            progress: { _ in }
        )
        defer { try? FileManager.default.removeItem(at: output) }

        #expect(output.lastPathComponent.hasSuffix("(slowed + reverb).mp4"))

        let asset = AVURLAsset(url: output)
        let video = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let audio = try #require(try await asset.loadTracks(withMediaType: .audio).first)

        // 0.5 s / 0.8 + 2.5 s reverb tail ≈ 3.125 s; the 0.375 s GIF loops to cover all of it.
        let audioSeconds = try await audio.load(.timeRange).duration.seconds
        let videoSeconds = try await video.load(.timeRange).duration.seconds
        #expect(abs(audioSeconds - 3.125) < 0.2)
        #expect(abs(videoSeconds - audioSeconds) < 0.05)

        let size = try await video.load(.naturalSize)
        #expect(Int(size.width) == VideoExporter.maxSide)
    }

    @Test func cancellationThrows() async throws {
        let source = try TestFixtures.makeAudioFile(duration: 0.5)
        let gif = try #require(AnimatedGIF(data: try TestFixtures.makeGIFData(delays: [0.1, 0.1]), maxPixelSize: 100))

        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await VideoExporter.export(
                source: source,
                title: "Video Cancel \(UUID().uuidString)",
                settings: .init(speed: 1, reverb: 0),
                gif: gif,
                progress: { _ in }
            )
        }
        await #expect(throws: CancellationError.self) {
            try await task.value
        }
    }
}

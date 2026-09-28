import AVFoundation
import CoreGraphics
import CoreVideo

/// Exports the processed track as an `.mp4`: the audio from `AudioExporter` over the
/// player's GIF, looped for the whole length of the track.
///
/// Only one GIF loop is encoded (H.264); the composition repeats it in time and the
/// final file is muxed without re-encoding, so long tracks stay fast to export.
nonisolated enum VideoExporter {
    enum Failure: Error {
        case writerFailed
        case missingTrack
        case exportFailed
    }

    /// Longer side of the video; small GIFs are scaled up so share targets don't reject them.
    static let maxSide = 720
    private static let timescale: CMTimeScale = 600

    // Share of the overall progress taken by each stage; rendering the audio dominates.
    private static let audioShare = 0.85
    private static let loopShare = 0.05

    /// Renders `source` with `settings` and puts it over `gif` looped at the track's speed
    /// (as in the player). Reports progress 0…1; supports task cancellation.
    @concurrent
    static func export(
        source: URL,
        title: String,
        settings: AudioExporter.Settings,
        gif: AnimatedGIF,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let workFolder = FileManager.default.temporaryDirectory
            .appending(path: "VideoExport-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: workFolder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workFolder) }

        let audioURL = try await AudioExporter.export(
            source: source,
            title: title,
            settings: settings,
            destination: workFolder.appending(path: "audio.m4a"),
            progress: { progress($0 * audioShare) }
        )

        try Task.checkCancellation()
        let loopURL = workFolder.appending(path: "loop.mp4")
        let loopDuration = try await writeLoop(of: gif, rate: Double(settings.speed), to: loopURL)
        progress(audioShare + loopShare)

        try Task.checkCancellation()
        let outputURL = try AudioExporter.makeOutputURL(title: title, settings: settings, fileExtension: "mp4")
        do {
            try await mux(loop: loopURL, loopDuration: loopDuration, audio: audioURL, to: outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        progress(1)
        return outputURL
    }

    // MARK: Stages

    /// Encodes one pass of the GIF, with frame delays stretched by the playback `rate`.
    /// Returns the loop's duration.
    private static func writeLoop(of gif: AnimatedGIF, rate: Double, to url: URL) async throws -> CMTime {
        let size = videoSize(for: gif.frames[0])
        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: 4_000_000,
                AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
            ]
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height
        ])
        guard writer.canAdd(input) else { throw Failure.writerFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? Failure.writerFailed }
        writer.startSession(atSourceTime: .zero)

        let times = frameTimes(delays: gif.delays, rate: rate)
        do {
            for (frame, time) in zip(gif.frames, times) {
                try Task.checkCancellation()
                while !input.isReadyForMoreMediaData {
                    try await Task.sleep(for: .milliseconds(2))
                }
                guard let pool = adaptor.pixelBufferPool,
                      let buffer = makePixelBuffer(from: frame, size: size, pool: pool),
                      adaptor.append(buffer, withPresentationTime: time)
                else { throw writer.error ?? Failure.writerFailed }
            }
        } catch {
            writer.cancelWriting()
            throw error
        }

        // The loop ends after the last frame's delay, so it repeats seamlessly.
        let duration = times.last ?? .zero
        input.markAsFinished()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? Failure.writerFailed }
        return duration
    }

    /// Lays the audio over back-to-back copies of the loop and writes the `.mp4` as is.
    private static func mux(loop loopURL: URL, loopDuration: CMTime, audio audioURL: URL, to outputURL: URL) async throws {
        let audioAsset = AVURLAsset(url: audioURL)
        let loopAsset = AVURLAsset(url: loopURL)
        let composition = AVMutableComposition()

        guard let audioSource = try await audioAsset.loadTracks(withMediaType: .audio).first,
              let videoSource = try await loopAsset.loadTracks(withMediaType: .video).first,
              let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid),
              let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw Failure.missingTrack }

        let audioRange = try await audioSource.load(.timeRange)
        try audioTrack.insertTimeRange(audioRange, of: audioSource, at: .zero)

        for range in loopRanges(total: audioRange.duration, loop: loopDuration) {
            try videoTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: range.duration),
                of: videoSource,
                at: range.start
            )
        }

        guard let session = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetPassthrough) else {
            throw Failure.exportFailed
        }
        try await session.export(to: outputURL, as: .mp4)
    }

    // MARK: Helpers

    /// Presentation time of each frame's end: running sum of delays / rate, in whole ticks.
    /// The first frame starts at zero, so frame `i` starts at `result[i - 1]`.
    static func frameEndTimes(delays: [TimeInterval], rate: Double) -> [CMTime] {
        var elapsed = 0.0
        return delays.map { delay in
            elapsed += delay / max(rate, 0.01)
            return CMTime(value: CMTimeValue((elapsed * Double(timescale)).rounded()), timescale: timescale)
        }
    }

    /// Start times of each frame followed by the loop's end, strictly increasing.
    private static func frameTimes(delays: [TimeInterval], rate: Double) -> [CMTime] {
        [.zero] + frameEndTimes(delays: delays, rate: rate)
    }

    /// Consecutive copies of a `loop`-long clip that cover `total`; the last one is trimmed.
    static func loopRanges(total: CMTime, loop: CMTime) -> [CMTimeRange] {
        guard loop > .zero else { return [] }
        var ranges: [CMTimeRange] = []
        var cursor = CMTime.zero
        while cursor < total {
            let piece = CMTimeMinimum(loop, total - cursor)
            ranges.append(CMTimeRange(start: cursor, duration: piece))
            cursor = cursor + piece
        }
        return ranges
    }

    /// Frame size scaled so the longer side is `maxSide`, rounded to even numbers for H.264.
    static func videoSize(width: Int, height: Int) -> (width: Int, height: Int) {
        let scale = Double(maxSide) / Double(max(width, height, 1))
        func even(_ value: Int) -> Int { max(2, Int((Double(value) * scale).rounded()) / 2 * 2) }
        return (even(width), even(height))
    }

    private static func videoSize(for frame: CGImage) -> (width: Int, height: Int) {
        videoSize(width: frame.width, height: frame.height)
    }

    /// Draws `frame` over black (GIFs may be transparent) into a BGRA buffer.
    private static func makePixelBuffer(from frame: CGImage, size: (width: Int, height: Int), pool: CVPixelBufferPool) -> CVPixelBuffer? {
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let buffer = pixelBuffer else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }

        guard let context = CGContext(
            data: CVPixelBufferGetBaseAddress(buffer),
            width: size.width,
            height: size.height,
            bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let rect = CGRect(x: 0, y: 0, width: size.width, height: size.height)
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(rect)
        context.interpolationQuality = .high
        context.draw(frame, in: rect)
        return buffer
    }
}

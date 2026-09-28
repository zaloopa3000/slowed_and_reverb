import AVFoundation

/// Renders a track through the same effect chain as playback
/// (player → mixer → varispeed → reverb) into an AAC `.m4a`, faster than real time.
nonisolated enum AudioExporter {
    struct Settings: Sendable {
        var speed: Float
        var reverb: Float
    }

    enum Failure: Error {
        case formatUnavailable
        case renderFailed
    }

    /// Extra time rendered after the track ends so the reverb tail can ring out.
    private static let reverbTail: TimeInterval = 2.5
    private static let maxFramesPerRender: AVAudioFrameCount = 4096

    /// Renders `source` with `settings`, reporting progress 0…1, and returns the new file's URL.
    /// Runs off the main actor; supports task cancellation (the partial file is removed).
    @concurrent
    static func export(
        source: URL,
        title: String,
        settings: Settings,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let input = try AVAudioFile(forReading: source)
        let sampleRate = input.processingFormat.sampleRate
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw Failure.formatUnavailable
        }

        // Same graph as live playback.
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let mixer = AVAudioMixerNode()
        let varispeed = AVAudioUnitVarispeed()
        let reverb = AVAudioUnitReverb()
        [player, mixer, varispeed, reverb].forEach(engine.attach)
        reverb.loadFactoryPreset(.largeHall)
        reverb.wetDryMix = settings.reverb
        varispeed.rate = settings.speed

        try connect(engine, player, to: mixer, format: input.processingFormat)
        try connect(engine, mixer, to: varispeed, format: stereo)
        try connect(engine, varispeed, to: reverb, format: stereo)
        try connect(engine, reverb, to: engine.mainMixerNode, format: stereo)

        try engine.enableManualRenderingMode(.offline, format: stereo, maximumFrameCount: maxFramesPerRender)
        try engine.start()
        defer { engine.stop() }

        player.scheduleFile(input, at: nil)
        if #available(iOS 27, *) {
            try player.playAudio()
        } else {
            player.play()
        }

        let outputURL = try makeOutputURL(title: title, settings: settings)
        let output = try AVAudioFile(
            forWriting: outputURL,
            settings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2,
                AVEncoderBitRateKey: 256_000
            ],
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: engine.manualRenderingFormat,
            frameCapacity: engine.manualRenderingMaximumFrameCount
        ) else { throw Failure.formatUnavailable }

        // Varispeed stretches time: output length = input length / rate.
        let totalFrames = AVAudioFramePosition(Double(input.length) / Double(settings.speed) + reverbTail * sampleRate)
        var lastReported = -1.0

        do {
            while engine.manualRenderingSampleTime < totalFrames {
                try Task.checkCancellation()
                let remaining = totalFrames - engine.manualRenderingSampleTime
                let frames = AVAudioFrameCount(min(AVAudioFramePosition(buffer.frameCapacity), remaining))

                switch try engine.renderOffline(frames, to: buffer) {
                case .success:
                    try output.write(from: buffer)
                case .cannotDoInCurrentContext, .insufficientDataFromInputNode:
                    continue
                case .error:
                    throw Failure.renderFailed
                @unknown default:
                    throw Failure.renderFailed
                }

                // Report in ~1% steps so the UI isn't flooded.
                let fraction = Double(engine.manualRenderingSampleTime) / Double(totalFrames)
                if fraction - lastReported >= 0.01 {
                    lastReported = fraction
                    progress(min(fraction, 1))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }

        progress(1)
        return outputURL
    }

    // MARK: Helpers

    private static func connect(_ engine: AVAudioEngine, _ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat) throws {
        if #available(iOS 27, *) {
            try engine.connectNode(source, to: destination, format: format)
        } else {
            engine.connect(source, to: destination, format: format)
        }
    }

    /// "<title> (slowed + reverb).m4a" in a temp "Exports" folder; replaces an older copy.
    private static func makeOutputURL(title: String, settings: Settings) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Exports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appending(path: fileName(title: title, settings: settings))
        if FileManager.default.fileExists(atPath: url.path()) {
            try FileManager.default.removeItem(at: url)
        }
        return url
    }

    static func fileName(title: String, settings: Settings) -> String {
        var tags: [String] = []
        if settings.speed < 0.999 { tags.append("slowed") }
        if settings.speed > 1.001 { tags.append("sped up") }
        if settings.reverb > 0 { tags.append("reverb") }

        // Keep the name safe for every share target.
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleanTitle = title.components(separatedBy: invalid).joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleanTitle.isEmpty ? "Tape" : cleanTitle
        let suffix = tags.isEmpty ? "" : " (\(tags.joined(separator: " + ")))"
        return base + suffix + ".m4a"
    }
}

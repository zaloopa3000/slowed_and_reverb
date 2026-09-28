import Accelerate
import AVFoundation
import Observation

/// Playback engine: player → input mixer → varispeed → reverb → main mixer.
///
/// Varispeed changes tempo and pitch together (tape-style), which is what gives
/// the classic "slowed" sound. The input mixer normalises any file format
/// (mono, 48 kHz, …) to stereo before the effects.
@Observable
final class AudioEngine {
    // MARK: Public state

    static let speedRange: ClosedRange<Float> = 0.5...1.5
    static let reverbRange: ClosedRange<Float> = 0...100

    private(set) var metadata: TrackMetadata = .empty
    /// Local copy of the loaded track (used for exporting).
    private(set) var sourceURL: URL?
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var isStereo = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// Fast winding in progress: -1 rewind, +1 fast-forward, 0 none.
    private(set) var windDirection = 0
    var errorMessage: String?

    /// Seconds of track skipped per winding tick (ticks run every 0.1 s → 9× speed).
    static let windStep: TimeInterval = 0.9

    /// Output levels for the L/R meter (observed separately from the engine).
    let meter = LevelMeter()

    /// Playback rate (tempo + pitch), 0.5…1.5.
    var speed: Float = 1.0 {
        didSet { varispeed.rate = speed }
    }

    /// Reverb wet/dry mix in percent, 0…100.
    var reverb: Float = 0 {
        didSet { reverbUnit.wetDryMix = reverb }
    }

    /// Playback progress, 0…1.
    var progress: Double {
        duration > 0 ? currentTime / duration : 0
    }

    // MARK: Engine graph

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private let inputMixer = AVAudioMixerNode()
    @ObservationIgnored private let varispeed = AVAudioUnitVarispeed()
    @ObservationIgnored private let reverbUnit = AVAudioUnitReverb()

    // MARK: Playback bookkeeping

    @ObservationIgnored private var file: AVAudioFile?
    @ObservationIgnored private var sampleRate: Double = 44_100
    /// Frame the currently scheduled segment starts from (player time is relative to it).
    @ObservationIgnored private var segmentStartFrame: AVAudioFramePosition = 0
    /// Whether the player needs a new segment scheduled before playing.
    @ObservationIgnored private var needsScheduling = true
    /// Incremented whenever scheduled audio is discarded, so stale completion callbacks are ignored.
    @ObservationIgnored private var scheduleGeneration = 0
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var windTask: Task<Void, Never>?
    @ObservationIgnored private var isMeterTapInstalled = false
    @ObservationIgnored private var notificationTasks: [Task<Void, Never>] = []
    @ObservationIgnored private var sessionConfigured = false

    init() {
        engine.attach(player)
        engine.attach(inputMixer)
        engine.attach(varispeed)
        engine.attach(reverbUnit)

        reverbUnit.loadFactoryPreset(.largeHall)
        reverbUnit.wetDryMix = reverb
        varispeed.rate = speed

        do {
            try connectEffectChain(sampleRate: sampleRate)
        } catch {
            errorMessage = "Audio engine setup failed."
        }
        observeSystemNotifications()
    }

    // MARK: Loading

    /// Copies a user-picked (security-scoped) file into the app's temp directory and loads it.
    func importTrack(from pickedURL: URL) async {
        let localURL: URL
        do {
            localURL = try await Self.copyIntoSandbox(pickedURL)
        } catch {
            print("Import: couldn't copy \(pickedURL.lastPathComponent): \(error)")
            errorMessage = "Couldn't read this file from its location.\n\(error.localizedDescription)"
            return
        }

        do {
            try await load(url: localURL)
        } catch {
            print("Import: couldn't decode \(localURL.lastPathComponent): \(error)")
            errorMessage = "This audio format isn't supported.\n\(error.localizedDescription)"
        }
    }

    /// Loads an audio file that the app can read directly.
    func load(url: URL) async throws {
        stop()
        engine.stop()
        meter.reset()

        let newFile = try AVAudioFile(forReading: url)
        let format = newFile.processingFormat

        file = newFile
        sourceURL = url
        sampleRate = format.sampleRate
        duration = Double(newFile.length) / format.sampleRate
        isStereo = format.channelCount >= 2
        currentTime = 0
        segmentStartFrame = 0
        needsScheduling = true

        // Rebuild the graph for this file's sample rate.
        engine.disconnectNodeOutput(player)
        try connect(player, to: inputMixer, format: format)
        try connectEffectChain(sampleRate: format.sampleRate)
        engine.prepare()

        isLoaded = true
        errorMessage = nil
        metadata = await TrackMetadata.load(from: url)
    }

    // MARK: Transport

    func togglePlayPause() {
        isPlaying ? pause() : play()
    }

    func play() {
        guard file != nil, !isPlaying else { return }

        // Restart from the top if the track already finished.
        if currentTime >= duration {
            currentTime = 0
            needsScheduling = true
        }

        do {
            try configureSessionIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            installMeterTapIfNeeded()
            if needsScheduling {
                scheduleSegment(from: frame(for: currentTime))
            }
            try startPlayerNode()
        } catch {
            errorMessage = "Audio engine failed to start."
            return
        }

        isPlaying = true
        errorMessage = nil
        startProgressUpdates()
    }

    func pause() {
        guard isPlaying else { return }
        updateCurrentTime()
        player.pause()
        isPlaying = false
        stopProgressUpdates()
    }

    /// Stops playback and rewinds to the start.
    func stop() {
        stopWinding()
        discardScheduledAudio()
        isPlaying = false
        stopProgressUpdates()
        currentTime = 0
        segmentStartFrame = 0
    }

    func seek(to time: TimeInterval) {
        guard file != nil else { return }
        let target = min(max(time, 0), duration)
        let wasPlaying = isPlaying

        discardScheduledAudio()
        currentTime = target

        // Nothing left to play: end of tape, like the natural end of the track.
        if target >= duration {
            isPlaying = false
            stopProgressUpdates()
            return
        }

        guard wasPlaying else { return }
        scheduleSegment(from: frame(for: target))
        do {
            try startPlayerNode()
        } catch {
            isPlaying = false
            stopProgressUpdates()
            errorMessage = "Playback failed."
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    /// Starts continuous fast winding (held ◀◀ / ▶▶). Audio is muted while winding,
    /// like a tape deck without cue; playback resumes normally once released.
    func startWinding(_ direction: Int) {
        guard isLoaded, direction != 0, windDirection != direction else { return }
        windTask?.cancel()
        windDirection = direction
        player.volume = 0

        windTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let target = currentTime + Double(direction) * Self.windStep
                seek(to: target)
                // Hit either end of the tape → stop winding.
                if target <= 0 || target >= duration {
                    stopWinding()
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    func stopWinding() {
        guard windDirection != 0 else { return }
        windTask?.cancel()
        windTask = nil
        windDirection = 0
        player.volume = 1
    }

    // MARK: - Private: metering

    /// Taps the main mixer (after all effects, so reverb shows on the meter too).
    private func installMeterTapIfNeeded() {
        guard !isMeterTapInstalled else { return }
        let mixer = engine.mainMixerNode
        if #available(iOS 27, *) {
            do {
                try mixer.installAudioTap(onBus: 0, bufferSize: 4096, format: nil, tapProvider: Self.makeMeterTap(meter: meter))
            } catch {
                return // Metering is cosmetic; playback works without it.
            }
        } else {
            mixer.installTap(onBus: 0, bufferSize: 4096, format: nil, block: Self.makeLegacyMeterTap(meter: meter))
        }
        isMeterTapInstalled = true
    }

    /// Offset from RMS dBFS to meter dB: a mix at -12 dBFS RMS reads 0 dB.
    private nonisolated static let meterCalibration: Float = 12
    /// Length of one meter chunk; the view steps through chunks at this rate.
    private nonisolated static let meterChunkDuration: TimeInterval = 0.02

    // The taps are built outside MainActor isolation: they run on an audio thread,
    // compute per-channel RMS for 20 ms chunks and hand only floats to the main actor.

    /// iOS 27+: read-only, sendable buffers.
    @available(iOS 27, *)
    private nonisolated static func makeMeterTap(
        meter: LevelMeter
    ) -> @Sendable (AVReadOnlyAudioPCMBuffer, AVAudioTime) -> Void {
        { buffer, _ in
            let frames = Int(buffer.frameLength)
            let chunkFrames = chunkFrameCount(sampleRate: buffer.format.sampleRate)

            func channelLevels(_ channel: Int) -> [Float] {
                guard case .float(let span) = buffer.channelData(channel) else { return [] }
                return span.withUnsafeBufferPointer { chunkLevels(of: $0, frames: frames, chunkFrames: chunkFrames) }
            }

            let left = channelLevels(0)
            let right = buffer.format.channelCount > 1 ? channelLevels(1) : left
            publish(left: left, right: right, to: meter)
        }
    }

    /// iOS 26: classic tap with `floatChannelData`.
    private nonisolated static func makeLegacyMeterTap(meter: LevelMeter) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channels = buffer.floatChannelData else { return }
            let frames = Int(buffer.frameLength)
            let chunkFrames = chunkFrameCount(sampleRate: buffer.format.sampleRate)

            func channelLevels(_ channel: Int) -> [Float] {
                chunkLevels(of: UnsafeBufferPointer(start: channels[channel], count: frames), frames: frames, chunkFrames: chunkFrames)
            }

            let left = channelLevels(0)
            let right = buffer.format.channelCount > 1 ? channelLevels(1) : left
            publish(left: left, right: right, to: meter)
        }
    }

    private nonisolated static func chunkFrameCount(sampleRate: Double) -> Int {
        max(Int(sampleRate * meterChunkDuration), 64)
    }

    /// RMS of each chunk of one channel's samples, converted to meter dB (Accelerate).
    private nonisolated static func chunkLevels(of samples: UnsafeBufferPointer<Float>, frames: Int, chunkFrames: Int) -> [Float] {
        guard let base = samples.baseAddress else { return [] }
        let count = min(frames, samples.count)
        return stride(from: 0, to: count, by: chunkFrames).map { start in
            var rms: Float = 0
            vDSP_rmsqv(base + start, 1, &rms, vDSP_Length(min(chunkFrames, count - start)))
            let db = 20 * log10(max(rms, 1e-7)) + meterCalibration
            return max(db, LevelMeter.floor)
        }
    }

    private nonisolated static func publish(left: [Float], right: [Float], to meter: LevelMeter) {
        let levels = zip(left, right).map { StereoLevel(left: $0, right: $1) }
        guard !levels.isEmpty else { return }
        Task { @MainActor in
            meter.push(levels, chunkDuration: meterChunkDuration)
        }
    }

    // MARK: - Private: graph

    /// input mixer → varispeed → reverb → main mixer, all in stereo at the given rate.
    private func connectEffectChain(sampleRate: Double) throws {
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        engine.disconnectNodeOutput(inputMixer)
        engine.disconnectNodeOutput(varispeed)
        engine.disconnectNodeOutput(reverbUnit)
        try connect(inputMixer, to: varispeed, format: stereo)
        try connect(varispeed, to: reverbUnit, format: stereo)
        try connect(reverbUnit, to: engine.mainMixerNode, format: stereo)
    }

    // MARK: - Private: OS-version shims

    /// `connectNode` (throwing) on iOS 27+, classic `connect` on iOS 26.
    private func connect(_ source: AVAudioNode, to destination: AVAudioNode, format: AVAudioFormat?) throws {
        if #available(iOS 27, *) {
            try engine.connectNode(source, to: destination, format: format)
        } else {
            engine.connect(source, to: destination, format: format)
        }
    }

    /// `playAudio` (throwing) on iOS 27+, classic `play` on iOS 26.
    private func startPlayerNode() throws {
        if #available(iOS 27, *) {
            try player.playAudio()
        } else {
            player.play()
        }
    }

    private func configureSessionIfNeeded() throws {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        sessionConfigured = true
    }

    // MARK: - Private: scheduling

    private func frame(for time: TimeInterval) -> AVAudioFramePosition {
        AVAudioFramePosition(time * sampleRate)
    }

    private func scheduleSegment(from startFrame: AVAudioFramePosition) {
        guard let file else { return }
        let start = min(max(startFrame, 0), file.length)
        let remaining = file.length - start
        guard remaining > 0 else { return }

        scheduleGeneration += 1
        segmentStartFrame = start
        needsScheduling = false

        let completion = Self.makeCompletionHandler(generation: scheduleGeneration) { [weak self] generation in
            self?.segmentDidFinish(generation: generation)
        }
        player.scheduleSegment(
            file,
            startingFrame: start,
            frameCount: AVAudioFrameCount(remaining),
            at: nil,
            completionCallbackType: .dataPlayedBack,
            completionHandler: completion
        )
    }

    /// Builds the completion handler outside MainActor isolation: AVFoundation
    /// calls it on an internal audio thread, so it just hops back to the main actor.
    private nonisolated static func makeCompletionHandler(
        generation: Int,
        onMain: @escaping @MainActor (Int) -> Void
    ) -> AVAudioPlayerNodeCompletionHandler {
        { _ in
            Task { @MainActor in onMain(generation) }
        }
    }

    /// Stops the player node and invalidates pending completion callbacks.
    private func discardScheduledAudio() {
        scheduleGeneration += 1
        player.stop()
        needsScheduling = true
    }

    private func segmentDidFinish(generation: Int) {
        // Ignore callbacks from segments discarded by seek/stop.
        guard generation == scheduleGeneration, isPlaying else { return }
        player.stop()
        isPlaying = false
        stopProgressUpdates()
        currentTime = duration
        needsScheduling = true
    }

    // MARK: - Private: progress

    private func startProgressUpdates() {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.updateCurrentTime()
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
    }

    private func stopProgressUpdates() {
        progressTask?.cancel()
        progressTask = nil
    }

    /// Reads the player node's position (in source frames) and converts it to seconds.
    private func updateCurrentTime() {
        guard let nodeTime = player.lastRenderTime,
              let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return }
        let seconds = Double(segmentStartFrame + playerTime.sampleTime) / sampleRate
        currentTime = min(max(seconds, 0), duration)
    }

    // MARK: - Private: system events

    private func observeSystemNotifications() {
        let center = NotificationCenter.default

        // Phone calls, Siri, other apps taking audio focus → pause.
        if #available(iOS 27, *) {
            // The system deactivates our session (the app itself never does).
            notificationTasks.append(Task { [weak self] in
                for await _ in center.notifications(named: AVAudioSession.didBecomeInactiveNotification) {
                    self?.pause()
                }
            })
        } else {
            notificationTasks.append(Task { [weak self] in
                for await note in center.notifications(named: AVAudioSession.interruptionNotification) {
                    let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                    if rawType.flatMap(AVAudioSession.InterruptionType.init) == .began {
                        self?.pause()
                    }
                }
            })
        }

        // Headphones unplugged → pause, like every other player.
        notificationTasks.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.routeChangeNotification) {
                let rawReason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                if rawReason.flatMap(AVAudioSession.RouteChangeReason.init) == .oldDeviceUnavailable {
                    self?.pause()
                }
            }
        })

        // The engine stops itself when the hardware configuration changes;
        // keep our position so the next play() resumes from the same spot.
        notificationTasks.append(Task { [weak self] in
            for await _ in center.notifications(named: .AVAudioEngineConfigurationChange) {
                self?.handleConfigurationChange()
            }
        })
    }

    private func handleConfigurationChange() {
        guard isLoaded else { return }
        if isPlaying { updateCurrentTime() }
        discardScheduledAudio()
        isPlaying = false
        stopProgressUpdates()
    }

    // MARK: - Private: files

    /// Copies a picked file into the app's temp folder, off the main actor.
    ///
    /// The picker hands out the *original* file (documents are opened in place), which may
    /// live in iCloud Drive or another provider and not be downloaded yet. A coordinated
    /// read makes the provider materialise it before copying.
    @concurrent
    private nonisolated static func copyIntoSandbox(_ url: URL) async throws -> URL {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }

        let fileManager = FileManager.default
        let folder = fileManager.temporaryDirectory.appending(path: "Imported", directoryHint: .isDirectory)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &coordinationError) { readableURL in
            do {
                if fileManager.fileExists(atPath: destination.path(percentEncoded: false)) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            throw error
        }
        return destination
    }
}

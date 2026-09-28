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

    /// Winding speed: seconds of track covered per second of holding ▶▶ / ◀◀.
    static let windRate: Double = 10
    private static let windTick: TimeInterval = 0.1

    private(set) var metadata: TrackMetadata = .empty
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var isStereo = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    /// The loaded file (a local copy for imported tracks); the source for exports.
    private(set) var sourceURL: URL?
    /// 1 while fast-forwarding, -1 while rewinding, 0 otherwise.
    private(set) var windDirection = 0
    var errorMessage: String?

    /// Post-effects L/R levels. A separate model so its frequent updates only redraw the meter.
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
    @ObservationIgnored private var wasPlayingBeforeWind = false
    @ObservationIgnored private var wasPlayingBeforeInterruption = false
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

        try? connectEffectChain(sampleRate: sampleRate)
        installLevelTap()
        observeSystemNotifications()
    }

    // MARK: Loading

    /// Copies a user-picked file into the app's container and loads it.
    func importTrack(from pickedURL: URL) async {
        do {
            let localURL = try await Self.importCopy(of: pickedURL)
            try await load(url: localURL)
            Self.removeImports(except: localURL)
        } catch {
            errorMessage = "Couldn't open this file."
        }
    }

    /// Loads an audio file that the app can read directly.
    func load(url: URL) async throws {
        stop()
        engine.stop()

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
        meter.reset()

        // Rebuild the graph for this file's sample rate.
        engine.disconnectNodeOutput(player)
        try engine.connectCompat(player, to: inputMixer, format: format)
        try connectEffectChain(sampleRate: format.sampleRate)
        engine.prepare()

        isLoaded = true
        errorMessage = nil
        metadata = await TrackMetadata.load(from: url)
    }

    // MARK: Transport

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    func play() {
        guard file != nil, !isPlaying else { return }
        cancelWinding()

        do {
            try configureSessionIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
            // Restart from the top if the track already finished.
            if currentTime >= duration {
                currentTime = 0
                needsScheduling = true
            }
            if needsScheduling {
                scheduleSegment(from: frame(for: currentTime))
            }
            try player.playCompat()
        } catch {
            errorMessage = "Audio engine failed to start."
            return
        }

        isPlaying = true
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
        cancelWinding()
        discardScheduledAudio()
        isPlaying = false
        stopProgressUpdates()
        currentTime = 0
        segmentStartFrame = 0
    }

    func seek(to time: TimeInterval) {
        guard file != nil else { return }
        cancelWinding()
        let target = min(max(time, 0), duration)
        let wasPlaying = isPlaying

        discardScheduledAudio()
        currentTime = target

        if wasPlaying {
            scheduleSegment(from: frame(for: target))
            do {
                try player.playCompat()
            } catch {
                isPlaying = false
                stopProgressUpdates()
            }
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    // MARK: Winding

    /// Starts fast-forward (`1`) or rewind (`-1`) while ▶▶ / ◀◀ is held; `0` stops.
    /// Audio is silent while winding, like a real deck; playback resumes on release.
    func startWinding(_ direction: Int) {
        guard file != nil else { return }
        guard direction != 0 else {
            stopWinding()
            return
        }

        if windDirection == 0 {
            wasPlayingBeforeWind = isPlaying
            if isPlaying {
                updateCurrentTime()
                haltPlayback()
            }
        }
        windDirection = direction > 0 ? 1 : -1

        windTask?.cancel()
        windTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Self.windTick))
                guard !Task.isCancelled, let self else { return }
                self.windStep()
            }
        }
    }

    /// Key released: stop winding and resume playback if it was playing before.
    func stopWinding() {
        guard windDirection != 0 else { return }
        let resume = wasPlayingBeforeWind && currentTime < duration
        cancelWinding()
        if resume {
            play()
        }
    }

    private func windStep() {
        let step = Self.windRate * Self.windTick * Double(windDirection)
        currentTime = min(max(currentTime + step, 0), duration)
        needsScheduling = true

        // The tape ran out: the deck stops winding by itself.
        let atEnd = windDirection > 0 && currentTime >= duration
        let atStart = windDirection < 0 && currentTime <= 0
        if atEnd || atStart {
            stopWinding()
        }
    }

    private func cancelWinding() {
        windTask?.cancel()
        windTask = nil
        windDirection = 0
        wasPlayingBeforeWind = false
    }

    // MARK: - Private: graph

    /// input mixer → varispeed → reverb → main mixer, all in stereo at the given rate.
    private func connectEffectChain(sampleRate: Double) throws {
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        engine.disconnectNodeOutput(inputMixer)
        engine.disconnectNodeOutput(varispeed)
        engine.disconnectNodeOutput(reverbUnit)
        try engine.connectCompat(inputMixer, to: varispeed, format: stereo)
        try engine.connectCompat(varispeed, to: reverbUnit, format: stereo)
        try engine.connectCompat(reverbUnit, to: engine.mainMixerNode, format: stereo)
    }

    private func configureSessionIfNeeded() throws {
        guard !sessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        sessionConfigured = true
    }

    // MARK: - Private: level meter

    /// Taps the main mixer (after all effects) and feeds the L/R meter.
    private func installLevelTap() {
        let block = Self.makeLevelTapBlock { [weak self] levels, chunkDuration in
            guard let self, self.isPlaying else { return }
            self.meter.push(levels, chunkDuration: chunkDuration)
        }
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 4096, format: nil, block: block)
    }

    /// Built outside MainActor isolation: the tap runs on an audio thread,
    /// so it measures the buffer there and only hands the result to the main actor.
    private nonisolated static func makeLevelTapBlock(
        onMain: @escaping @MainActor ([StereoLevel], TimeInterval) -> Void
    ) -> AVAudioNodeTapBlock {
        { buffer, _ in
            guard let channels = buffer.floatChannelData, buffer.frameLength > 0 else { return }
            let frames = Int(buffer.frameLength)
            let sampleRate = buffer.format.sampleRate
            let chunkFrames = max(Int(sampleRate * LevelMeter.chunkLength), 1)

            let left = UnsafeBufferPointer(start: channels[0], count: frames)
            let right = buffer.format.channelCount > 1
                ? UnsafeBufferPointer(start: channels[1], count: frames)
                : left
            let levels = LevelMeter.levels(left: left, right: right, chunkFrames: chunkFrames)
            let chunkDuration = Double(chunkFrames) / sampleRate

            Task { @MainActor in onMain(levels, chunkDuration) }
        }
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

    /// Stops the audio but keeps `currentTime`, so the next `play()` resumes from it.
    private func haltPlayback() {
        discardScheduledAudio()
        isPlaying = false
        stopProgressUpdates()
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
                guard let self else { return }
                self.updateCurrentTime()
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

        // Phone calls, Siri, other apps taking audio focus.
        notificationTasks.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.interruptionNotification) {
                let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                let rawOptions = (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
                guard let type = rawType.flatMap(AVAudioSession.InterruptionType.init) else { continue }
                let shouldResume = AVAudioSession.InterruptionOptions(rawValue: rawOptions).contains(.shouldResume)
                self?.handleInterruption(type, shouldResume: shouldResume)
            }
        })

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

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, shouldResume: Bool) {
        switch type {
        case .began:
            wasPlayingBeforeInterruption = isPlaying
            if isPlaying {
                updateCurrentTime()
                // The system may stop the engine, so reschedule from here on resume.
                haltPlayback()
            }
        case .ended:
            // Resume after a call only if we were playing and the system allows it.
            if wasPlayingBeforeInterruption && shouldResume {
                play()
            }
            wasPlayingBeforeInterruption = false
        @unknown default:
            break
        }
    }

    private func handleConfigurationChange() {
        guard isLoaded else { return }
        if isPlaying { updateCurrentTime() }
        cancelWinding()
        haltPlayback()
    }

    // MARK: - Private: files

    private nonisolated static var importFolder: URL {
        FileManager.default.temporaryDirectory.appending(path: "Imported", directoryHint: .isDirectory)
    }

    /// Copies a picked file into a fresh folder in the app's temp directory, off the main actor.
    /// Coordinated reading makes iCloud Drive download files that aren't on the device yet.
    @concurrent
    private nonisolated static func importCopy(of pickedURL: URL) async throws -> URL {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }

        // A unique folder per import keeps the original file name and never clashes
        // with the track that is currently loaded.
        let folder = importFolder.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: pickedURL.lastPathComponent)

        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: pickedURL, options: [], error: &coordinationError) { readableURL in
            do {
                try FileManager.default.copyItem(at: readableURL, to: destination)
            } catch {
                copyError = error
            }
        }
        if let error = coordinationError ?? copyError {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return destination
    }

    /// Deletes earlier imports so copies of old tracks don't pile up in temp.
    private static func removeImports(except keptURL: URL) {
        let keptFolder = keptURL.deletingLastPathComponent().standardizedFileURL
        let folders = (try? FileManager.default.contentsOfDirectory(at: importFolder, includingPropertiesForKeys: nil)) ?? []
        for folder in folders where folder.standardizedFileURL != keptFolder {
            try? FileManager.default.removeItem(at: folder)
        }
    }
}

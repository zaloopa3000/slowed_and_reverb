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
    private(set) var isLoaded = false
    private(set) var isPlaying = false
    private(set) var isStereo = false
    private(set) var currentTime: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    var errorMessage: String?

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

        connectEffectChain(sampleRate: sampleRate)
        observeSystemNotifications()
    }

    // MARK: Loading

    /// Copies a user-picked (security-scoped) file into the app's temp directory and loads it.
    func importTrack(from pickedURL: URL) async {
        let accessing = pickedURL.startAccessingSecurityScopedResource()
        defer { if accessing { pickedURL.stopAccessingSecurityScopedResource() } }

        do {
            let localURL = try Self.copyToTemporaryDirectory(pickedURL)
            try await load(url: localURL)
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
        sampleRate = format.sampleRate
        duration = Double(newFile.length) / format.sampleRate
        isStereo = format.channelCount >= 2
        currentTime = 0
        segmentStartFrame = 0
        needsScheduling = true

        // Rebuild the graph for this file's sample rate.
        engine.disconnectNodeOutput(player)
        engine.connect(player, to: inputMixer, format: format)
        connectEffectChain(sampleRate: format.sampleRate)
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

        do {
            try configureSessionIfNeeded()
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            errorMessage = "Audio engine failed to start."
            return
        }

        // Restart from the top if the track already finished.
        if currentTime >= duration {
            currentTime = 0
            needsScheduling = true
        }
        if needsScheduling {
            scheduleSegment(from: frame(for: currentTime))
        }

        player.play()
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

        if wasPlaying {
            scheduleSegment(from: frame(for: target))
            player.play()
        }
    }

    func skip(by seconds: TimeInterval) {
        seek(to: currentTime + seconds)
    }

    // MARK: - Private: graph

    /// input mixer → varispeed → reverb → main mixer, all in stereo at the given rate.
    private func connectEffectChain(sampleRate: Double) {
        guard let stereo = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else { return }
        engine.disconnectNodeOutput(inputMixer)
        engine.disconnectNodeOutput(varispeed)
        engine.disconnectNodeOutput(reverbUnit)
        engine.connect(inputMixer, to: varispeed, format: stereo)
        engine.connect(varispeed, to: reverbUnit, format: stereo)
        engine.connect(reverbUnit, to: engine.mainMixerNode, format: stereo)
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

        // Phone calls, Siri, other apps taking audio focus.
        notificationTasks.append(Task { [weak self] in
            for await note in center.notifications(named: AVAudioSession.interruptionNotification) {
                let rawType = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                if rawType.flatMap(AVAudioSession.InterruptionType.init) == .began {
                    self?.pause()
                }
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

    private func handleConfigurationChange() {
        guard isLoaded else { return }
        if isPlaying { updateCurrentTime() }
        discardScheduledAudio()
        isPlaying = false
        stopProgressUpdates()
    }

    // MARK: - Private: files

    private static func copyToTemporaryDirectory(_ url: URL) throws -> URL {
        let folder = FileManager.default.temporaryDirectory.appending(path: "Imported", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appending(path: url.lastPathComponent)
        if FileManager.default.fileExists(atPath: destination.path()) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: url, to: destination)
        return destination
    }
}

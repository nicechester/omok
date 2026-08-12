import AVFoundation
import AVFoundation
import Combine
import os

actor AudioPlaybackEngine {
    nonisolated private let audioBuffer = AudioStreamBuffer(capacity: 4410)
    private let isReceivingAudioSubject = PassthroughSubject<Bool, Never>()

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var lastScheduledSequence: UInt32 = 0
    private var frameBuffer: [AudioFrame] = []
    private var isPlaying = false
    private let logger = Logger(subsystem: "io.github.nicechester.omok", category: "audio.playback")
    private var receiveTimeoutTimer: Timer?
    private var lastReceiveTime: Date = Date()
    private let receiveTimeoutInterval: TimeInterval = 0.4
    private var outputGain: Float = 1.8

    nonisolated var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioBuffer.audioLevelPublisher.eraseToAnyPublisher()
    }

    nonisolated var audioSamplesPublisher: AnyPublisher<[Float], Never> {
        audioBuffer.audioSamplesPublisher.eraseToAnyPublisher()
    }

    nonisolated var isReceivingAudioPublisher: AnyPublisher<Bool, Never> {
        isReceivingAudioSubject.eraseToAnyPublisher()
    }

    init() {
        audioEngine.attach(playerNode)

        // Use 48000 Hz to match the capture hardware format
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!

        audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: format)
    }

    /// Start playback engine.
    func start() async throws {
        do {
            try audioEngine.start()
            if !playerNode.isPlaying {
                playerNode.play()
                isPlaying = true
            }
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .defaultToSpeaker)
            try AVAudioSession.sharedInstance().setActive(true)

            // Observe interruptions
            observeInterruptions()

            // Start receive timeout monitoring
            startReceiveTimeoutMonitoring()

            logger.debug("Audio playback engine started")
        } catch {
            logger.error("Failed to start playback engine: \(error.localizedDescription)")
            throw error
        }
    }

    /// Stop playback engine.
    func stop() async throws {
        playerNode.stop()
        isPlaying = false
        try audioEngine.stop()
        receiveTimeoutTimer?.invalidate()
        receiveTimeoutTimer = nil
        frameBuffer.removeAll()
        isReceivingAudioSubject.send(false)
        logger.debug("Audio playback engine stopped")
    }

    /// Set the output gain multiplier for audio playback.
    func setOutputGain(_ gain: Float) {
        self.outputGain = gain
    }

    /// Enqueue a received frame for playback.
    /// Drops frames out of order or already scheduled.
    /// Implements jitter buffering: holds until 2 frames before scheduling.
    func enqueue(_ frame: AudioFrame) async {
        logger.debug("Enqueue called with frame sequence: \(frame.sequence)")
        // Reset timeout on new frame received
        lastReceiveTime = Date()
        isReceivingAudioSubject.send(true)

        // Drop out-of-order frames
        if frame.sequence <= self.lastScheduledSequence {
            logger.debug("Dropping duplicate/out-of-order frame: \(frame.sequence), last scheduled: \(self.lastScheduledSequence)")
            return
        }

        self.frameBuffer.append(frame)
        self.frameBuffer.sort { $0.sequence < $1.sequence }
        logger.debug("Frame buffered. Buffer count: \(self.frameBuffer.count)")

        // Jitter buffering: schedule only when we have at least 2 frames
        while self.frameBuffer.count >= 2 {
            let frame = self.frameBuffer.removeFirst()
            await scheduleFrame(frame)
            self.lastScheduledSequence = frame.sequence
            logger.debug("Scheduled frame sequence: \(frame.sequence)")
        }
    }

    /// Schedule a frame for playback on the AVAudioPlayerNode.
    private func scheduleFrame(_ frame: AudioFrame) {
        let floatSamples = AudioFrame.dequantize(frame.samples)
        let gain = outputGain
        let amplified = floatSamples.map { max(-1.0, min(1.0, $0 * gain)) }
        guard let audioBuffer = createAudioBuffer(from: amplified) else {
            logger.error("Failed to create audio buffer for frame \(frame.sequence)")
            return
        }

        // Feed rectified (absolute value) samples into the waveform buffer
        let rectifiedSamples = amplified.map { abs($0) }
        self.audioBuffer.append(samples: rectifiedSamples)

        playerNode.scheduleBuffer(audioBuffer)
        logger.debug("Scheduled frame: \(frame.sequence)")
    }

    /// Create an AVAudioPCMBuffer from Float samples.
    private func createAudioBuffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 48000,
            channels: 1,
            interleaved: false
        )!

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for (i, sample) in samples.enumerated() {
            channelData[i] = sample
        }

        return buffer
    }

    /// Monitor receive timeout: if no new frames for ~400ms, emit false.
    private func startReceiveTimeoutMonitoring() {
        receiveTimeoutTimer?.invalidate()
        receiveTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task {
                await self?.checkReceiveTimeout()
            }
        }
    }

    private func checkReceiveTimeout() async {
        let elapsed = Date().timeIntervalSince(lastReceiveTime)
        if elapsed > receiveTimeoutInterval && isPlaying {
            isReceivingAudioSubject.send(false)
        }
    }

    /// Observe AVAudioSession interruptions.
    private func observeInterruptions() {
        NotificationCenter.default.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            guard let userInfo = notification.userInfo,
                  let typeValue = userInfo["AVAudioSessionInterruptionTypeKey"] as? UInt,
                  let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }

            Task {
                await self?.handleInterruption(type, userInfo: userInfo)
            }
        }
    }

    private func handleInterruption(_ type: AVAudioSession.InterruptionType, userInfo: [AnyHashable: Any]) async {
        switch type {
        case .began:
            if isPlaying {
                playerNode.pause()
                logger.debug("Audio playback paused due to interruption")
            }
        case .ended:
            if let optionsValue = userInfo["AVAudioSessionInterruptionOptionsKey"] as? UInt {
                if (optionsValue & AVAudioSession.InterruptionOptions.shouldResume.rawValue) != 0 {
                    if !playerNode.isPlaying && isPlaying {
                        playerNode.play()
                        logger.debug("Audio playback resumed after interruption")
                    }
                }
            }
        @unknown default:
            break
        }
    }

    deinit {
        receiveTimeoutTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
}

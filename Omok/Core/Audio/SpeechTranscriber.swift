import Foundation
import Speech
import Combine
import AVFoundation

actor SpeechTranscriber {
    nonisolated private let updatesSubject = PassthroughSubject<(text: String, isFinal: Bool), Never>()
    private var recognizer: SFSpeechRecognizer?
    private var currentRequest: SFSpeechAudioBufferRecognitionRequest?
    private var currentTask: SFSpeechRecognitionTask?
    private var isStoppedManually = false
    private var audioBufferFormat: AVAudioFormat?

    nonisolated var updatesPublisher: AnyPublisher<(text: String, isFinal: Bool), Never> {
        updatesSubject.eraseToAnyPublisher()
    }

    func start() async {
        isStoppedManually = false

        // Request authorization
        let authorized = await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
        guard authorized else {
            print("[SpeechTranscriber] Not authorized for speech recognition")
            return
        }

        // Initialize recognizer with current locale
        let recognizer = SFSpeechRecognizer(locale: Locale.current)
        self.recognizer = recognizer

        // Check availability and on-device support
        guard let recognizer = recognizer, recognizer.isAvailable else {
            print("[SpeechTranscriber] Recognizer not available")
            return
        }

        guard recognizer.supportsOnDeviceRecognition else {
            print("[SpeechTranscriber] On-device recognition not supported")
            return
        }

        print("[SpeechTranscriber] Starting speech recognition")
        // Start the first request/task pair
        await startNewRequest()
    }

    func append(samples: [Float]) async {
        guard let request = currentRequest else {
            print("[SpeechTranscriber] No current request, samples dropped")
            return
        }

        // Create or reuse audio buffer format
        if audioBufferFormat == nil {
            audioBufferFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48000,
                channels: 1,
                interleaved: false
            )
        }

        guard let format = audioBufferFormat else {
            print("[SpeechTranscriber] No audio format")
            return
        }

        // Create PCM buffer from samples
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)) else {
            print("[SpeechTranscriber] Failed to create buffer")
            return
        }

        buffer.frameLength = AVAudioFrameCount(samples.count)
        let channelData = buffer.floatChannelData![0]
        for (i, sample) in samples.enumerated() {
            channelData[i] = sample
        }

        request.append(buffer)
    }

    func stop() async {
        isStoppedManually = true
        currentRequest?.endAudio()
        currentTask?.cancel()
        currentRequest = nil
        currentTask = nil
    }

    private func startNewRequest() async {
        guard !isStoppedManually, let recognizer = recognizer, recognizer.isAvailable else {
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = true

        let task = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task {
                await self?.handleRecognitionResult(result, error: error, request: request)
            }
        }

        self.currentRequest = request
        self.currentTask = task
    }

    private func handleRecognitionResult(
        _ result: SFSpeechRecognitionResult?,
        error: Error?,
        request: SFSpeechAudioBufferRecognitionRequest
    ) async {
        // Publish text if available
        if let result = result {
            let text = result.bestTranscription.formattedString
            let isFinal = result.isFinal

            if !text.isEmpty {
                print("[SpeechTranscriber] Text: '\(text)' (final: \(isFinal))")
                updatesSubject.send((text: text, isFinal: isFinal))
            }

            // If final, tear down and restart
            if isFinal {
                print("[SpeechTranscriber] Utterance final, restarting")
                currentRequest = nil
                currentTask = nil
                await startNewRequest()
            }
        }

        // On error, also restart (unless manually stopped)
        if error != nil {
            print("[SpeechTranscriber] Error: \(error?.localizedDescription ?? "unknown")")
            currentRequest = nil
            currentTask = nil
            if !isStoppedManually {
                await startNewRequest()
            }
        }
    }
}

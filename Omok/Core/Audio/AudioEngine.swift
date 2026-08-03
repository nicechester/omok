import AVFoundation
import AVFoundation
import Combine

actor AudioEngine {
    private let audioEngine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var audioBuffer: AudioStreamBuffer?
    private let rawSamplesSubject = PassthroughSubject<[Float], Never>()

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioBuffer?.audioLevelPublisher ?? Empty().eraseToAnyPublisher()
    }

    var audioSamplesPublisher: AnyPublisher<[Float], Never> {
        audioBuffer?.audioSamplesPublisher ?? Empty().eraseToAnyPublisher()
    }

    nonisolated var rawSamplesPublisher: AnyPublisher<[Float], Never> {
        rawSamplesSubject.eraseToAnyPublisher()
    }

    init() {
        self.inputNode = audioEngine.inputNode
    }

    func startCapture() async throws {
        // Set up audio session FIRST, before accessing input node format
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .defaultToSpeaker)
        try AVAudioSession.sharedInstance().setActive(true)
        
        // Get the actual hardware format - DON'T hardcode the sample rate!
        // The hardware will be 48000 Hz on modern devices
        let inputFormat = inputNode.outputFormat(forBus: 0)
        
        // Use the hardware sample rate for buffer size calculation
        let sampleRate = inputFormat.sampleRate
        let bufferSize = AVAudioFrameCount(sampleRate * 0.1) // 100ms buffer
        
        // Create buffer with capacity matching the sample rate
        audioBuffer = AudioStreamBuffer(capacity: Int(sampleRate * 0.1))
        
        // CRITICAL: Use inputFormat for the tap - it must match the hardware format
        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            Task {
                await self.processAudioBuffer(buffer)
            }
        }

        try audioEngine.start()
    }

    func stopCapture() async throws {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try AVAudioSession.sharedInstance().setActive(false)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let floatChannelData = buffer.floatChannelData,
              let audioBuffer = audioBuffer else { return }

        let frameLength = Int(buffer.frameLength)
        let channelData = floatChannelData[0]

        var samples = [Float]()
        var rawSamples = [Float]()
        samples.reserveCapacity(frameLength)
        rawSamples.reserveCapacity(frameLength)

        for i in 0..<frameLength {
            rawSamples.append(channelData[i])
            samples.append(abs(channelData[i]))
        }

        await audioBuffer.append(samples: samples)
        rawSamplesSubject.send(rawSamples)
    }
}

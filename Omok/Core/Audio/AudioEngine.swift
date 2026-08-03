import AVFoundation
import Combine

actor AudioEngine {
    private let audioEngine = AVAudioEngine()
    private let inputNode: AVAudioInputNode
    private var audioBuffer = AudioStreamBuffer(capacity: 4410)

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioBuffer.audioLevelPublisher.eraseToAnyPublisher()
    }

    var audioSamplesPublisher: AnyPublisher<[Float], Never> {
        audioBuffer.audioSamplesPublisher.eraseToAnyPublisher()
    }

    init() {
        self.inputNode = audioEngine.inputNode
    }

    func startCapture() async throws {
        let inputFormat = inputNode.outputFormat(forBus: 0) ?? AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )!

        let audioFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44100,
            channels: 1,
            interleaved: false
        )!

        inputNode.installTap(onBus: 0, bufferSize: 4410, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            Task {
                await self.processAudioBuffer(buffer)
            }
        }

        audioEngine.attachNode(inputNode)
        audioEngine.connect(inputNode, to: audioEngine.mainMixerNode, format: audioFormat)

        try audioEngine.start()
        try AVAudioSession.sharedInstance().setCategory(.playAndRecord, options: .defaultToSpeaker)
        try AVAudioSession.sharedInstance().setActive(true)
    }

    func stopCapture() async throws {
        inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        try AVAudioSession.sharedInstance().setActive(false)
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) async {
        guard let floatChannelData = buffer.floatChannelData else { return }

        let frameLength = Int(buffer.frameLength)
        let channelData = floatChannelData[0]

        var samples = [Float]()
        samples.reserveCapacity(frameLength)

        for i in 0..<frameLength {
            samples.append(abs(channelData[i]))
        }

        await audioBuffer.append(samples: samples)
    }
}

import Combine
import Foundation

class AudioStreamBuffer {
    private let capacity: Int
    private var samples: [Float] = []
    private let audioLevelSubject = PassthroughSubject<Float, Never>()
    private let audioSamplesSubject = PassthroughSubject<[Float], Never>()

    var audioLevelPublisher: AnyPublisher<Float, Never> {
        audioLevelSubject.eraseToAnyPublisher()
    }

    var audioSamplesPublisher: AnyPublisher<[Float], Never> {
        audioSamplesSubject.eraseToAnyPublisher()
    }

    init(capacity: Int) {
        self.capacity = capacity
    }

    func append(samples newSamples: [Float]) {
        samples.append(contentsOf: newSamples)

        if samples.count > capacity {
            samples.removeFirst(samples.count - capacity)
        }

        let averageLevel = samples.isEmpty ? 0 : samples.reduce(0, +) / Float(samples.count)
        audioLevelSubject.send(averageLevel)
        audioSamplesSubject.send(samples)
    }

    func reset() {
        samples.removeAll()
    }
}

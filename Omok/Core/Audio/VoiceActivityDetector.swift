import Foundation
import AVFoundation

actor VoiceActivityDetector {
    private let silenceThreshold: Float = 0.05
    private let debounceInterval: TimeInterval = 0.1
    private var lastUpdateTime: Date = .distantPast
    private var currentSpeakingState = false

    func detectSpeaking(audioLevel: Float) -> Bool {
        let isSpeaking = audioLevel > silenceThreshold
        let now = Date()

        if isSpeaking != currentSpeakingState &&
           now.timeIntervalSince(lastUpdateTime) >= debounceInterval {
            currentSpeakingState = isSpeaking
            lastUpdateTime = now
            return true
        }

        return false
    }

    func reset() {
        currentSpeakingState = false
        lastUpdateTime = .distantPast
    }
}

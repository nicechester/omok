import Firebase
import os

actor FirebaseAudioMessenger {
    nonisolated private let db = Database.database()
    nonisolated private let logger = Logger(subsystem: "io.github.nicechester.omok", category: "audio.firebase")

    private let gameId: String
    private let uid: String
    private var incomingFramesContinuation: AsyncStream<AudioFrame>.Continuation?
    private var listenerHandle: DatabaseHandle?
    nonisolated private let incomingFramesStream: AsyncStream<AudioFrame>

    nonisolated var incomingFrames: AsyncStream<AudioFrame> {
        incomingFramesStream
    }

    init(gameId: String, uid: String) {
        self.gameId = gameId
        self.uid = uid

        var continuation: AsyncStream<AudioFrame>.Continuation?
        let stream = AsyncStream<AudioFrame> { c in
            continuation = c
        }
        incomingFramesStream = stream
        self.incomingFramesContinuation = continuation

        startListeningForFrames()
    }

    /// Start listening for incoming audio frames from opponent.
    private func startListeningForFrames() {
        let framesRef = db.reference().child("omok/games/\(self.gameId)/audioFrames")

        listenerHandle = framesRef.observe(.childAdded) { [weak self] snapshot in
            guard let self = self,
                  let frameData = snapshot.value as? [String: Any] else { return }

            if let frame = AudioFrame.fromDictionary(frameData) {
                Task {
                    await self.handleReceivedFrame(frame)
                }
            }
        }

        logger.debug("Started listening for audio frames in game: \(self.gameId)")
    }

    /// Handle a received audio frame.
    private func handleReceivedFrame(_ frame: AudioFrame) {
        incomingFramesContinuation?.yield(frame)
        logger.debug("Received audio frame sequence: \(frame.sequence)")
    }

    /// Send raw audio samples to Firebase.
    func send(rawSamples: [Float]) async {
        let quantized = AudioFrame.quantize(rawSamples)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)

        let frame = AudioFrame(
            sequence: UInt32.random(in: 0..<UInt32.max),
            samples: quantized,
            timestamp: timestamp
        )

        let frameDict = frame.toDictionary()
        let frameRef = db.reference()
            .child("omok/games/\(self.gameId)/audioFrames")
            .childByAutoId()

        frameRef.setValue(frameDict) { [weak self] error, _ in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("Failed to send audio frame: \(error.localizedDescription)")
            } else {
                self.logger.debug("Sent audio frame sequence: \(frame.sequence)")
            }
        }
    }

    /// Stop listening for frames and clean up.
    func cleanup() async {
        if let handle = listenerHandle {
            db.reference()
                .child("omok/games/\(gameId)/audioFrames")
                .removeObserver(withHandle: handle)
        }
        incomingFramesContinuation?.finish()
        logger.debug("Audio messenger cleaned up")
    }

    deinit {
        logger.debug("FirebaseAudioMessenger deinit")
    }
}

extension AudioFrame {
    /// Convert to dictionary for Firebase storage.
    func toDictionary() -> [String: Any] {
        return [
            "sequence": sequence,
            "samples": samples.map { NSNumber(value: $0) },
            "timestamp": timestamp
        ]
    }

    /// Create from Firebase dictionary.
    static func fromDictionary(_ dict: [String: Any]) -> AudioFrame? {
        guard let sequence = dict["sequence"] as? UInt32,
              let samplesArray = dict["samples"] as? [NSNumber],
              let timestamp = dict["timestamp"] as? UInt64 else {
            return nil
        }

        let samples = samplesArray.map { Int16(truncatingIfNeeded: $0.int16Value) }
        return AudioFrame(sequence: sequence, samples: samples, timestamp: timestamp)
    }
}

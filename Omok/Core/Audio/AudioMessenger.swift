import Foundation
import FirebaseDatabase
import os

actor AudioMessenger {
    private let database: DatabaseReference
    private var nextSequenceToSend: UInt32 = 0
    private var incomingFramesContinuation: AsyncStream<AudioFrame>.Continuation?
    private var receiveTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "io.github.nicechester.omok", category: "audio.messenger")
    private let incomingFramesStream: AsyncStream<AudioFrame>
    
    private let gameId: String
    private let uid: String
    private var observerHandles: [DatabaseHandle] = []
    
    private var audioRef: DatabaseReference {
        database.child("omok/audio").child(gameId)
    }
    
    private var myAudioRef: DatabaseReference {
        audioRef.child(uid)
    }
    
    var incomingFrames: AsyncStream<AudioFrame> {
        incomingFramesStream
    }
    
    init(gameId: String, uid: String, database: DatabaseReference = Database.database().reference()) {
        self.gameId = gameId
        self.uid = uid
        self.database = database
        
        var continuation: AsyncStream<AudioFrame>.Continuation?
        incomingFramesStream = AsyncStream<AudioFrame> { c in
            continuation = c
        }
        incomingFramesContinuation = continuation
    }
    
    /// Start listening for incoming audio from other players
    func startObservingSessions() {
        receiveTask?.cancel()
        receiveTask = Task {
            await self.receiveFrames()
        }
        
        logger.debug("Started observing audio frames for game: \(self.gameId), uid: \(self.uid)")
    }
    
    /// Listen for audio frames from all other players
    private func receiveFrames() async {
        logger.debug("Setting up Firebase audio listeners...")
        
        // Listen to childAdded events under the audio path
        let handle = audioRef.observe(.childAdded) { [weak self] snapshot in
            guard let self = self else { return }
            
            Task {
                await self.handlePlayerAudioNode(snapshot: snapshot)
            }
        }
        
        observerHandles.append(handle)
        logger.debug("Firebase audio listener attached")
    }
    
    /// Handle a player's audio node being added
    private func handlePlayerAudioNode(snapshot: DataSnapshot) async {
        let playerUid = snapshot.key
        
        // Ignore our own audio stream
        guard playerUid != self.uid else {
            logger.debug("Ignoring own audio stream")
            return
        }
        
        logger.debug("Found opponent audio stream: \(playerUid)")
        
        // Listen to frame updates from this opponent
        let frameHandle = snapshot.ref.observe(.childAdded) { [weak self] frameSnapshot in
            guard let self = self else { return }
            
            Task {
                await self.handleIncomingFrame(frameSnapshot: frameSnapshot)
            }
        }
        
        observerHandles.append(frameHandle)
    }
    
    /// Handle an incoming audio frame
    private func handleIncomingFrame(frameSnapshot: DataSnapshot) async {
        guard let frame = decodeAudioFrame(from: frameSnapshot) else {
            logger.warning("Failed to decode audio frame")
            return
        }
        
        incomingFramesContinuation?.yield(frame)
        
        if frame.sequence % 50 == 0 {
            logger.debug("Received frame sequence: \(frame.sequence)")
        }
        
        // Delete the frame after processing to prevent memory buildup
        do {
            try await frameSnapshot.ref.removeValue()
        } catch {
            logger.error("Failed to remove processed frame: \(error.localizedDescription)")
        }
    }
    
    /// Send raw audio samples to Firebase
    func send(rawSamples: [Float]) async {
        let quantized = AudioFrame.quantize(rawSamples)
        let timestamp = UInt64(Date().timeIntervalSince1970 * 1000)
        
        let frame = AudioFrame(
            sequence: nextSequenceToSend,
            samples: quantized,
            timestamp: timestamp
        )
        
        nextSequenceToSend += 1
        
        // Send to Firebase
        let frameData: [String: Any] = [
            "sequence": frame.sequence,
            "samples": frame.samples,
            "timestamp": frame.timestamp
        ]
        
        do {
            // Use sequence number as the child key for ordering
            try await myAudioRef.child("\(frame.sequence)").setValue(frameData)
            
            if nextSequenceToSend % 50 == 1 {
                logger.debug("Sent frame sequence: \(frame.sequence)")
            }
            
            // Cleanup old frames periodically
            if nextSequenceToSend % 100 == 0 {
                await cleanupOldFrames()
            }
        } catch {
            logger.error("Failed to send audio frame: \(error.localizedDescription)")
        }
    }
    
    /// Remove frames older than current sequence - 50 to prevent buildup
    private func cleanupOldFrames() async {
        guard nextSequenceToSend > 50 else { return }
        
        let cutoff = nextSequenceToSend - 50
        
        do {
            let snapshot = try await myAudioRef.getData()
            for child in snapshot.children {
                guard let childSnapshot = child as? DataSnapshot else { continue }
                
                // The key is the sequence number
                if let sequence = UInt32(childSnapshot.key), sequence < cutoff {
                    try? await childSnapshot.ref.removeValue()
                }
            }
        } catch {
            logger.debug("Cleanup skipped: \(error.localizedDescription)")
        }
    }
    
    /// Decode AudioFrame from Firebase snapshot
    private func decodeAudioFrame(from snapshot: DataSnapshot) -> AudioFrame? {
        guard let dict = snapshot.value as? [String: Any] else {
            return nil
        }
        
        guard let sequence = dict["sequence"] as? UInt32,
              let timestamp = dict["timestamp"] as? UInt64 else {
            return nil
        }
        
        // Handle samples as either [Int16] or [Int] (Firebase may convert types)
        let samples: [Int16]
        if let int16Samples = dict["samples"] as? [Int16] {
            samples = int16Samples
        } else if let intSamples = dict["samples"] as? [Int] {
            samples = intSamples.map { Int16(clamping: $0) }
        } else if let nsNumbers = dict["samples"] as? [NSNumber] {
            samples = nsNumbers.map { Int16(clamping: $0.intValue) }
        } else {
            return nil
        }
        
        return AudioFrame(sequence: sequence, samples: samples, timestamp: timestamp)
    }
    
    /// Cleanup: remove all observers and our audio stream
    func cleanup() async {
        logger.debug("Cleaning up AudioMessenger...")
        
        receiveTask?.cancel()
        incomingFramesContinuation?.finish()
        
        // Remove all Firebase observers
        for handle in observerHandles {
            audioRef.removeObserver(withHandle: handle)
        }
        observerHandles.removeAll()
        
        // Remove our audio stream from Firebase
        do {
            try await myAudioRef.removeValue()
            logger.debug("Cleaned up audio stream for uid: \(self.uid)")
        } catch {
            logger.error("Failed to cleanup audio stream: \(error.localizedDescription)")
        }
    }
}

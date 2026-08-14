import SwiftUI
import SwiftUI
import Observation
import AVFoundation
import Combine

struct GameView: View {
    let gameId: String
    let uid: String
    let playerName: String
    var onLeave: (() -> Void)? = nil
    let timerDuration: Int?
    let aiDifficulty: AIDifficulty?

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @AppStorage(AudioOutputSettings.storageKey) private var audioOutputLevel: Int = AudioOutputSettings.defaultLevel.rawValue
    @State private var viewModel: GameViewModel
    @State private var showExitConfirmation = false
    @State private var showForfeitConfirmation = false
    @State private var showUndoPrompt = false
    @State private var isMicEnabled = false
    @State private var isSpeaking = false
    @State private var opponentSpeaking = false
    @State private var vadDetector = VoiceActivityDetector()
    @State private var audioEngine = AudioEngine()
    @State private var audioMessenger: AudioMessenger
    @State private var audioPlaybackEngine = AudioPlaybackEngine()
    @State private var audioLevel: Float = 0
    @State private var audioSamples: [Float] = []
    @State private var opponentAudioSamples: [Float] = []
    @State private var isReceivingOpponentAudio = false
    @State private var audioLevelCancellable: AnyCancellable?
    @State private var audioSamplesCancellable: AnyCancellable?
    @State private var rawSamplesCancellable: AnyCancellable?
    @State private var playbackSamplesCancellable: AnyCancellable?
    @State private var receivingAudioCancellable: AnyCancellable?
    @State private var micWasEnabledBeforeBackground = false
    @State private var opponentTranscriber = SpeechTranscriber()
    @State private var transcripts: [TranscriptEntry] = []
    @State private var opponentTranscriptSamplesCancellable: AnyCancellable?
    @State private var opponentTranscriptUpdatesCancellable: AnyCancellable?
    @State private var voiceChatStarted = false

    init(gameId: String, uid: String, playerName: String, aiDifficulty: AIDifficulty? = nil, onLeave: (() -> Void)? = nil, timerDuration: Int? = nil) {
        self.gameId = gameId
        self.uid = uid
        self.playerName = playerName
        self.onLeave = onLeave
        self.timerDuration = timerDuration
        self.aiDifficulty = aiDifficulty

        let repository: GameRepository
        if let difficulty = aiDifficulty {
            repository = LocalGameRepository(difficulty: difficulty, localUid: uid)
        } else {
            repository = FirebaseGameRepository()
        }

        _viewModel = State(initialValue: GameViewModel(
            gameId: gameId,
            uid: uid,
            playerName: playerName,
            timerDuration: timerDuration,
            aiDifficulty: aiDifficulty,
            repository: repository
        ))
        _audioMessenger = State(initialValue: AudioMessenger(gameId: gameId, uid: uid))
    }

    private func applyOutputGain() {
        let level = AudioOutputSettings.VolumeLevel(rawValue: audioOutputLevel) ?? .normal
        Task {
            await audioPlaybackEngine.setOutputGain(level.multiplier)
        }
    }

    private func toggleMicrophone() {
        if !isMicEnabled {
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                if granted {
                    isMicEnabled = true
                    startAudioCapture()
                }
            }
        } else {
            isMicEnabled = false
            stopAudioCapture()
        }
    }

    private func startAudioCapture() {
        Task {
            do {
                try await audioEngine.startCapture()

                audioLevelCancellable = await audioEngine.audioLevelPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { level in
                        audioLevel = level
                        processAudioLevel(level)
                    }

                audioSamplesCancellable = await audioEngine.audioSamplesPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { samples in
                        audioSamples = samples
                    }

                // rawSamplesPublisher is nonisolated, no await needed
                rawSamplesCancellable = audioEngine.rawSamplesPublisher
                    .sink { rawSamples in
                        Task {
                            await audioMessenger.send(rawSamples: rawSamples)
                        }
                    }
            } catch {
                print("Failed to start audio capture: \(error)")
                isMicEnabled = false
            }
        }
    }

    private func stopAudioCapture() {
        Task {
            do {
                try await audioEngine.stopCapture()
                audioLevelCancellable?.cancel()
                audioSamplesCancellable?.cancel()
                rawSamplesCancellable?.cancel()
                audioLevel = 0
                audioSamples = []
                await updateSpeakingState(false)
            } catch {
                print("Failed to stop audio capture: \(error)")
            }
        }
    }

    private func processAudioLevel(_ level: Float) {
        Task {
            if await vadDetector.detectSpeaking(audioLevel: level) {
                let shouldBeSpeaking = level > 0.05
                if isSpeaking != shouldBeSpeaking {
                    isSpeaking = shouldBeSpeaking
                    await updateSpeakingState(shouldBeSpeaking)
                }
            }
        }
    }

    private func updateSpeakingState(_ isSpeaking: Bool) async {
        await viewModel.updateSpeaking(isSpeaking)
    }

    private func startVoiceChat() {
        Task {
            do {
                // Start playback engine
                try await audioPlaybackEngine.start()

                // Apply stored audio output gain preference
                let level = AudioOutputSettings.VolumeLevel(rawValue: audioOutputLevel) ?? .normal
                await audioPlaybackEngine.setOutputGain(level.multiplier)

                // Subscribe to playback engine's audio publishers (nonisolated, no await needed)
                playbackSamplesCancellable = audioPlaybackEngine.audioSamplesPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { samples in
                        opponentAudioSamples = samples
                    }

                receivingAudioCancellable = audioPlaybackEngine.isReceivingAudioPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { isReceiving in
                        isReceivingOpponentAudio = isReceiving
                    }

                // Subscribe to opponent audio for speech recognition
                opponentTranscriptSamplesCancellable = audioPlaybackEngine.rawPlaybackSamplesPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { samples in
                        Task {
                            await opponentTranscriber.append(samples: samples)
                        }
                    }

                // Start opponent transcriber
                Task { await opponentTranscriber.start() }

                // Subscribe to opponent transcriber updates
                opponentTranscriptUpdatesCancellable = await opponentTranscriber.updatesPublisher
                    .receive(on: DispatchQueue.main)
                    .sink { text, isFinal in
                        applyTranscriptUpdate((text: text, isFinal: isFinal), speaker: viewModel.mySeat?.opposite)
                    }

                // Start receiving incoming audio frames from Firebase
                Task {
                    for await frame in await audioMessenger.incomingFrames {
                        await audioPlaybackEngine.enqueue(frame)
                    }
                }

                print("Voice chat session initiated via Firebase")
            } catch {
                print("Failed to activate voice chat: \(error)")
            }
        }
    }

    @ViewBuilder
    private var actionsSection: some View {
        if viewModel.game?.status != .finished {
            VStack(spacing: 8) {
                if isMicEnabled || opponentSpeaking {
                    WaveformView(
                        localSamples: audioSamples,
                        opponentSamples: opponentAudioSamples,
                        isLocalActive: isSpeaking,
                        isOpponentActive: opponentSpeaking
                    )
                    .frame(height: 40)
                }

                HStack(spacing: 16) {
                    Button(action: toggleMicrophone) {
                        Image(systemName: isMicEnabled ? "mic.fill" : "mic.slash.fill")
                            .font(.system(size: 18))
                            .foregroundColor(isMicEnabled ? .blue : .gray)
                    }

                    Spacer()

                    // Undo button
                    if viewModel.canRequestUndo {
                        Button(action: {
                            Task {
                                await viewModel.requestUndo()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.uturn.left")
                                    .font(.system(size: 14))
                                Text("Undo")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.blue)
                        }
                    } else if viewModel.undoRequestPending {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.uturn.left")
                                .font(.system(size: 14))
                            Text("Undo…")
                                .font(.subheadline)
                        }
                        .foregroundColor(.gray)
                    }

                    Spacer()

                    // Show forfeit button only if user is a player (not spectator) and game is active
                    if viewModel.mySeat != nil, viewModel.game?.status == .playing {
                        Button(action: {
                            showForfeitConfirmation = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "flag.fill")
                                    .font(.system(size: 14))
                                Text("Resign")
                                    .font(.subheadline)
                            }
                            .foregroundColor(.red)
                        }
                    }
                }
                .frame(height: 44)
            }
            .padding(.horizontal)
        }
    }

    private var mainContent: some View {
        VStack(spacing: 0) {
            GameStatusBar(
                gameId: gameId,
                statusText: viewModel.statusText,
                mySeat: viewModel.mySeat,
                myName: playerName,
                players: viewModel.game?.players ?? [:],
                remainingSeconds: viewModel.remainingSeconds,
                scores: viewModel.game?.scores ?? [:],
                onLeave: {
                    viewModel.markPlayerAsDisconnected()
                    onLeave?()
                }
            )

            BoardView(
                gameState: viewModel.game,
                canPlay: viewModel.canPlay,
                onTap: { cell in
                    Task {
                        await viewModel.place(cell)
                    }
                }
            )
            .padding()

            Spacer()

            if !transcripts.isEmpty {
                TranscriptBannerView(transcripts: transcripts, mySeat: viewModel.mySeat)
                    .padding(.horizontal)
            }

            actionsSection
        }
    }

    @ViewBuilder
    private var resultOverlay: some View {
        if viewModel.game?.status == .finished {
            VStack {
                Spacer()
                ResultBanner(
                    result: viewModel.game?.result,
                    isSpectator: viewModel.isSpectator,
                    isMyWin: viewModel.isMyWin,
                    didVoteRematch: viewModel.didVoteRematch,
                    onRematchTapped: {
                        Task {
                            await viewModel.requestRematch()
                        }
                    }
                )
                .padding(.bottom, 90)
            }
        }
    }

    var body: some View {
        ZStack {
            mainContent
            resultOverlay
        }
        .navigationBarBackButtonHidden()
        .confirmationDialog("Leave Game?", isPresented: $showExitConfirmation) {
            Button("Leave", role: .destructive) {
                onLeave?()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stay in the game and can rejoin by entering the room code again.")
        }
        .confirmationDialog("Resign Game?", isPresented: $showForfeitConfirmation) {
            Button("Resign", role: .destructive) {
                Task {
                    await viewModel.forfeit()
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to resign? Your opponent will win the game.")
        }
        .confirmationDialog("Undo Request", isPresented: $showUndoPrompt) {
            Button("Approve") {
                Task {
                    await viewModel.approveUndo()
                }
            }
            Button("Cancel", role: .cancel) {
                Task {
                    await viewModel.rejectUndo()
                }
            }
        } message: {
            let requesterName = viewModel.undoRequesterName ?? "Opponent"
            Text("\(requesterName) wants to undo their last move. Do you approve?")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred.")
        }
        .task {
            viewModel.isViewVisible = true
            await audioMessenger.startObservingSessions()
            recentRoomsData = RecentRooms.recordPlay(code: gameId, aiDifficulty: aiDifficulty, in: recentRoomsData)
            await viewModel.start()
            viewModel.markPlayerAsActive()
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.setScenePhase(newPhase)
            if newPhase == .background {
                // Pause audio capture when backgrounding
                if isMicEnabled {
                    micWasEnabledBeforeBackground = true
                    stopAudioCapture()
                    isMicEnabled = false
                }
                viewModel.appDidEnterBackground()
            } else if newPhase == .active {
                // Resume audio capture if it was enabled before background
                if micWasEnabledBeforeBackground {
                    isMicEnabled = true
                    startAudioCapture()
                    micWasEnabledBeforeBackground = false
                }
                viewModel.appDidBecomeActive()
            }
        }
        .onDisappear {
            viewModel.isViewVisible = false
            handleDisappear()
        }
        .onChange(of: viewModel.game?.status) { _, newStatus in
            handleStatusChange(newStatus)
        }
        .onChange(of: viewModel.game?.speaking) { _, newSpeaking in
            if let mySeat = viewModel.mySeat {
                let opponentSeat = (mySeat == .black ? Stone.white : Stone.black)
                if let isOpponentSpeaking = newSpeaking?[opponentSeat] {
                    opponentSpeaking = isOpponentSpeaking
                }
            }
        }
        .onChange(of: viewModel.showUndoPrompt) { _, newValue in
            showUndoPrompt = newValue
        }
    }

    private func applyTranscriptUpdate(_ update: (text: String, isFinal: Bool), speaker: Stone?) {
        print("[GameView] applyTranscriptUpdate: speaker=\(String(describing: speaker)), text='\(update.text)', isFinal=\(update.isFinal), currentCount=\(transcripts.count)")

        if let existing = transcripts.firstIndex(where: { $0.speaker == speaker && !$0.isFinal }) {
            print("[GameView] Found existing non-final entry for speaker, updating")
            transcripts[existing].text = update.text
            transcripts[existing].updatedAt = Date()
            if update.isFinal {
                transcripts[existing].isFinal = true
                // Schedule 6s expiry
                let entryId = transcripts[existing].id
                Task {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    transcripts.removeAll { $0.id == entryId }
                }
            }
        } else if !update.text.isEmpty {
            print("[GameView] Creating new transcript entry for speaker")
            let entry = TranscriptEntry(
                id: UUID(),
                speaker: speaker,
                text: update.text,
                isFinal: update.isFinal,
                startedAt: Date(),
                updatedAt: Date()
            )
            transcripts.append(entry)
            print("[GameView] Entry added, total count: \(transcripts.count)")
            if update.isFinal {
                Task {
                    try? await Task.sleep(nanoseconds: 6_000_000_000)
                    transcripts.removeAll { $0.id == entry.id }
                }
            }
        }
        // Cap at ~5 entries
        if transcripts.count > 5 {
            transcripts.removeFirst(transcripts.count - 5)
        }
    }

    private func handleDisappear() {
        voiceChatStarted = false
        viewModel.markPlayerAsDisconnected()

        // Pause timer when leaving GameView (navigating to other tabs or screens)
        viewModel.pauseTimer()

        Task {
            await audioMessenger.cleanup()
            if isMicEnabled {
                try? await audioEngine.stopCapture()
            }
            try? await audioPlaybackEngine.stop()
            await updateSpeakingState(false)

            // Stop opponent transcriber
            await opponentTranscriber.stop()
        }
        audioLevelCancellable?.cancel()
        audioSamplesCancellable?.cancel()
        rawSamplesCancellable?.cancel()
        playbackSamplesCancellable?.cancel()
        receivingAudioCancellable?.cancel()
        opponentTranscriptSamplesCancellable?.cancel()
        opponentTranscriptUpdatesCancellable?.cancel()
    }

    private func handleStatusChange(_ newStatus: GameStatus?) {
        if newStatus == .playing && viewModel.game?.players.count == 2 && !voiceChatStarted && !viewModel.isAIGame {
            voiceChatStarted = true
            startVoiceChat()
        } else if newStatus == .finished {
            voiceChatStarted = false
            if isMicEnabled {
                stopAudioCapture()
                isMicEnabled = false
            }
            Task {
                await updateSpeakingState(false)

                // Stop opponent transcriber when game finishes
                await opponentTranscriber.stop()
            }
        }
    }
}

#Preview {
    GameView(gameId: "abc12", uid: "user1", playerName: "Chester", aiDifficulty: nil)
}

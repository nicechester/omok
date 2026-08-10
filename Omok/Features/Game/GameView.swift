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

    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @State private var viewModel: GameViewModel
    @State private var showExitConfirmation = false
    @State private var showForfeitConfirmation = false
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

    init(gameId: String, uid: String, playerName: String, onLeave: (() -> Void)? = nil) {
        self.gameId = gameId
        self.uid = uid
        self.playerName = playerName
        self.onLeave = onLeave
        _viewModel = State(initialValue: GameViewModel(
            gameId: gameId,
            uid: uid,
            playerName: playerName,
            repository: FirebaseGameRepository()
        ))
        _audioMessenger = State(initialValue: AudioMessenger(gameId: gameId, uid: uid))
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
                players: viewModel.game?.players ?? [:]
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
                Spacer()
            }
        }
    }

    var body: some View {
        ZStack {
            mainContent
            resultOverlay
        }
        .navigationBarBackButtonHidden()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                let isWaiting = viewModel.game?.status == .waiting && viewModel.mySeat == nil
                let buttonText = isWaiting ? "Cancel" : "Leave"

                Button(buttonText) {
                    if viewModel.game?.status == .finished {
                        onLeave?()
                    } else if isWaiting {
                        onLeave?()
                    } else {
                        showExitConfirmation = true
                    }
                }
            }
        }
        .alert("Leave Game?", isPresented: $showExitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Leave", role: .destructive) {
                onLeave?()
            }
        } message: {
            Text("You'll stay in the game and can rejoin by entering the room code again.")
        }
        .alert("Resign Game?", isPresented: $showForfeitConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Resign", role: .destructive) {
                Task {
                    await viewModel.forfeit()
                }
            }
        } message: {
            Text("Are you sure you want to resign? Your opponent will win the game.")
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred.")
        }
        .task {
            await audioMessenger.startObservingSessions()
            recentRoomsData = RecentRooms.recordPlay(code: gameId, in: recentRoomsData)
            await viewModel.start()
        }
        .onDisappear {
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
    }

    private func handleDisappear() {
        Task {
            await audioMessenger.cleanup()
            if isMicEnabled {
                try? await audioEngine.stopCapture()
            }
            try? await audioPlaybackEngine.stop()
            await updateSpeakingState(false)
        }
        audioLevelCancellable?.cancel()
        audioSamplesCancellable?.cancel()
        rawSamplesCancellable?.cancel()
        playbackSamplesCancellable?.cancel()
        receivingAudioCancellable?.cancel()
    }

    private func handleStatusChange(_ newStatus: GameStatus?) {
        if newStatus == .playing && viewModel.game?.players.count == 2 {
            startVoiceChat()
        } else if newStatus == .finished {
            if isMicEnabled {
                stopAudioCapture()
                isMicEnabled = false
            }
            Task {
                await updateSpeakingState(false)
            }
        }
    }
}

#Preview {
    GameView(gameId: "abc12", uid: "user1", playerName: "Chester")
}

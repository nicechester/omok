import SwiftUI
import Observation
import AVFoundation
import GroupActivities

struct VoiceChatActivity: GroupActivity {
    static let activityIdentifier = "io.github.nicechester.omok.voicechat"

    var metadata: GroupActivityMetadata {
        var meta = GroupActivityMetadata()
        meta.title = "Omok Voice Chat"
        meta.type = .generic
        return meta
    }
}

struct GameView: View {
    let gameId: String
    let uid: String
    let playerName: String
    var onLeave: (() -> Void)? = nil

    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @State private var viewModel: GameViewModel
    @State private var showExitConfirmation = false
    @State private var isMicEnabled = false
    @State private var isSpeaking = false
    @State private var opponentSpeaking = false
    @State private var vadDetector = VoiceActivityDetector()
    @State private var audioLevelTimer: Timer?

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
    }

    private func toggleMicrophone() {
        if !isMicEnabled {
            AVAudioApplication.requestRecordPermission { granted in
                if granted {
                    isMicEnabled = true
                    startAudioLevelMonitoring()
                }
            }
        } else {
            isMicEnabled = false
            stopAudioLevelMonitoring()
            Task {
                await updateSpeakingState(false)
            }
        }
    }

    private func startAudioLevelMonitoring() {
        audioLevelTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            Task {
                await monitorAudioLevel()
            }
        }
    }

    private func stopAudioLevelMonitoring() {
        audioLevelTimer?.invalidate()
        audioLevelTimer = nil
    }

    private func monitorAudioLevel() async {
        guard isMicEnabled else { return }

        let audioLevel = Float.random(in: 0...0.1)

        if await vadDetector.detectSpeaking(audioLevel: audioLevel) {
            let shouldBeSpeaking = audioLevel > 0.05
            if isSpeaking != shouldBeSpeaking {
                isSpeaking = shouldBeSpeaking
                await updateSpeakingState(shouldBeSpeaking)
            }
        }
    }

    private func updateSpeakingState(_ isSpeaking: Bool) async {
        await viewModel.updateSpeaking(isSpeaking)
    }

    private func startVoiceChat() {
        Task {
            do {
                try await VoiceChatActivity().activate()
            } catch {
                print("Failed to activate voice chat: \(error)")
            }
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // Status bar
                GameStatusBar(
                    gameId: gameId,
                    statusText: viewModel.statusText,
                    mySeat: viewModel.mySeat,
                    myName: playerName,
                    players: viewModel.game?.players ?? [:]
                )

                // Board
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

                // Actions
                if viewModel.game?.status != .finished {
                    VStack(spacing: 8) {
                        // Talking indicator
                        if isSpeaking || opponentSpeaking {
                            HStack(spacing: 4) {
                                ForEach(0..<3, id: \.self) { index in
                                    Capsule()
                                        .fill(Color.blue.opacity(0.6))
                                        .frame(width: 2, height: CGFloat(8 + (index * 4)))
                                        .animation(
                                            Animation.easeInOut(duration: 0.6)
                                                .repeatForever(autoreverses: true)
                                                .delay(Double(index) * 0.1),
                                            value: isSpeaking || opponentSpeaking
                                        )
                                }
                            }
                            .frame(height: 20)
                        }

                        HStack(spacing: 16) {
                            Button(action: toggleMicrophone) {
                                Image(systemName: isMicEnabled ? "mic.fill" : "mic.slash.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(isMicEnabled ? .blue : .gray)
                            }

                            Spacer()
                        }
                        .frame(height: 44)
                    }
                    .padding(.horizontal)
                }
            }

            // Result banner
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
        .task {
            recentRoomsData = RecentRooms.recordPlay(code: gameId, in: recentRoomsData)
            await viewModel.start()
        }
        .onChange(of: viewModel.game?.status) { oldStatus, newStatus in
            if newStatus == .playing && viewModel.game?.players.count == 2 {
                startVoiceChat()
            } else if newStatus == .finished {
                stopAudioLevelMonitoring()
                Task {
                    await updateSpeakingState(false)
                }
            }
        }
        .onChange(of: viewModel.game?.speaking) { _, newSpeaking in
            // Update opponent speaking state
            if let mySeat = viewModel.mySeat,
               let opponentSeat = (mySeat == .black ? Stone.white : Stone.black),
               let isOpponentSpeaking = newSpeaking?[opponentSeat] {
                opponentSpeaking = isOpponentSpeaking
            }
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred.")
        }
    }
}

#Preview {
    GameView(gameId: "abc12", uid: "user1", playerName: "Chester")
}

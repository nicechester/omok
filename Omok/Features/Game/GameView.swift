import SwiftUI

struct GameView: View {
    let gameId: String
    let uid: String
    let playerName: String
    var onLeave: (() -> Void)? = nil
    let timerDuration: Int?
    let aiDifficulty: AIDifficulty?

    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @State private var viewModel: GameViewModel
    @State private var showExitConfirmation = false
    @State private var showForfeitConfirmation = false
    @State private var showUndoPrompt = false
    @State private var showEmojiTray = false
    @State private var showEmojiPicker = false

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
    }

    @ViewBuilder
    private var actionsSection: some View {
        if viewModel.game?.status != .finished {
            VStack(spacing: 8) {
                HStack(spacing: 16) {
                    if viewModel.mySeat != nil, viewModel.game?.status == .playing {
                        Button(action: { showEmojiTray.toggle() }) {
                            Image(systemName: "face.smiling")
                                .font(.system(size: 18))
                                .foregroundColor(showEmojiTray ? .blue : .gray)
                        }
                    }

                    Spacer()

                    if viewModel.canRequestUndo {
                        Button(action: { Task { await viewModel.requestUndo() } }) {
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

                    if viewModel.mySeat != nil, viewModel.game?.status == .playing {
                        Button(action: { showForfeitConfirmation = true }) {
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

                if showEmojiTray {
                    let quickEmoji = ["1F604", "1F62E", "1F44F", "1F914", "1F605"]
                    HStack(spacing: 16) {
                        ForEach(quickEmoji, id: \.self) { hexcode in
                            Button {
                                showEmojiTray = false
                                Task { await viewModel.sendReaction(hexcode) }
                            } label: {
                                OpenMojiImage(hexcode: hexcode)
                                    .frame(width: 36, height: 36)
                            }
                            .buttonStyle(.plain)
                        }
                        Button {
                            showEmojiTray = false
                            showEmojiPicker = true
                        } label: {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 20))
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                    .transition(.opacity)
                }
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
                    Task { await viewModel.place(cell) }
                }
            )
            .padding()

            Spacer()

            if let reaction = viewModel.pendingReaction {
                OpenMojiImage(hexcode: reaction.emoji)
                    .frame(width: 96, height: 96)
                    .transition(.scale.combined(with: .opacity))
                    .id(reaction.timestamp)
                    .animation(.spring(duration: 0.3), value: reaction.timestamp)
                    .allowsHitTesting(false)
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
                    onRematchTapped: { Task { await viewModel.requestRematch() } }
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
            Button("Leave", role: .destructive) { onLeave?() }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("You'll stay in the game and can rejoin by entering the room code again.")
        }
        .confirmationDialog("Resign Game?", isPresented: $showForfeitConfirmation) {
            Button("Resign", role: .destructive) { Task { await viewModel.forfeit() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to resign? Your opponent will win the game.")
        }
        .confirmationDialog("Undo Request", isPresented: $showUndoPrompt) {
            Button("Approve") { Task { await viewModel.approveUndo() } }
            Button("Cancel", role: .cancel) { Task { await viewModel.rejectUndo() } }
        } message: {
            let requesterName = viewModel.undoRequesterName ?? "Opponent"
            Text("\(requesterName) wants to undo their last move. Do you approve?")
        }
        .sheet(isPresented: $showEmojiPicker) {
            EmojiPickerSheet { emoji in
                Task { await viewModel.sendReaction(emoji) }
            }
            .presentationDetents([.medium, .large])
        }
        .alert("Error", isPresented: .constant(viewModel.errorMessage != nil)) {
            Button("OK") { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "An error occurred.")
        }
        .task {
            viewModel.isViewVisible = true
            recentRoomsData = RecentRooms.recordPlay(code: gameId, aiDifficulty: aiDifficulty, in: recentRoomsData)
            await viewModel.start()
            if !viewModel.isSpectator { viewModel.markPlayerAsActive() }
        }
        .onChange(of: scenePhase) { _, newPhase in
            viewModel.setScenePhase(newPhase)
            if newPhase == .background {
                viewModel.appDidEnterBackground()
            } else if newPhase == .active {
                viewModel.appDidBecomeActive()
            }
        }
        .onDisappear {
            viewModel.isViewVisible = false
            viewModel.markPlayerAsDisconnected()
            viewModel.pauseTimer()
        }
        .onChange(of: viewModel.showUndoPrompt) { _, newValue in
            showUndoPrompt = newValue
        }
    }
}

#Preview {
    GameView(gameId: "abc12", uid: "user1", playerName: "Chester", aiDifficulty: nil)
}

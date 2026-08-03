import SwiftUI
import Observation

struct GameView: View {
    let gameId: String
    let uid: String
    let playerName: String
    var onLeave: (() -> Void)? = nil

    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @State private var viewModel: GameViewModel
    @State private var showExitConfirmation = false

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
                    HStack {
                        Text("")
                    }
                    .frame(height: 44)
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

import SwiftUI
import Observation

struct GameView: View {
    let gameId: String
    let isCreator: Bool
    let uid: String
    let playerName: String

    @State private var viewModel: GameViewModel
    @Environment(\.dismiss) var dismiss

    init(gameId: String, isCreator: Bool, uid: String, playerName: String) {
        self.gameId = gameId
        self.isCreator = isCreator
        self.uid = uid
        self.playerName = playerName
        _viewModel = State(initialValue: GameViewModel(
            gameId: gameId,
            uid: uid,
            playerName: playerName,
            repository: FirebaseGameRepository(),
            isCreator: isCreator
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
                    opponentName: viewModel.opponentName
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

            // Waiting for opponent overlay
            if viewModel.game?.status == .waiting {
                ZStack {
                    Color.black.opacity(0.4)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)

                        VStack(spacing: 8) {
                            Text("Waiting for opponent")
                                .font(.headline)
                            Text("Share code: \(gameId)")
                                .font(.title2)
                                .monospaced()
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(24)
                    .background(Color(.systemBackground))
                    .cornerRadius(12)
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
        .task {
            await viewModel.start()
        }
        .alert("Game Not Found", isPresented: $viewModel.gameNotFound) {
            Button("Back", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("No game found with code \(gameId). Check the code and try again.")
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
    GameView(gameId: "abc12", isCreator: true, uid: "user1", playerName: "Chester")
}

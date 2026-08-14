import SwiftUI

struct PlayView: View {
    let uid: String
    @Binding var activeGameId: String?
    @Binding var aiDifficulty: AIDifficulty?
    @Binding var pendingGameCode: String?

    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @State private var showNewGame = false

    var body: some View {
        if let gameId = activeGameId {
            GameView(gameId: gameId, uid: uid, playerName: playerName, aiDifficulty: aiDifficulty, onLeave: { activeGameId = nil })
                .id(gameId)
        } else {
            ContentUnavailableView {
                Label("No Active Game", systemImage: "circle.grid.3x3")
            } description: {
                Text("Join a recent room or start a new game")
            } actions: {
                Button("New Game") { showNewGame = true }
                    .buttonStyle(.borderedProminent)
            }
            .sheet(isPresented: $showNewGame) {
                NewGameSheet(uid: uid, onJoin: { code, difficulty in
                    aiDifficulty = difficulty
                    activeGameId = code
                    showNewGame = false
                })
            }
            .onChange(of: pendingGameCode) { _, newCode in
                if let code = newCode {
                    activeGameId = code
                    pendingGameCode = nil
                }
            }
        }
    }
}

#Preview {
    PlayView(uid: "user1", activeGameId: .constant(nil), aiDifficulty: .constant(nil), pendingGameCode: .constant(nil))
}

import SwiftUI

struct GameStatusBar: View {
    let gameId: String
    let statusText: String
    let mySeat: Stone?
    let myName: String
    let players: [Stone: PlayerSeat]

    @State private var showCopyFeedback = false

    var body: some View {
        VStack(spacing: 4) {
            // Top row: room code + status
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text(gameId)
                        .font(.headline)
                        .monospaced()
                        .fontWeight(.semibold)
                    Button(action: {
                        UIPasteboard.general.string = gameId
                        showCopyFeedback = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            showCopyFeedback = false
                        }
                    }) {
                        Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                            .foregroundColor(showCopyFeedback ? .green : .blue)
                    }
                    ShareLink(
                        item: URL(string: "omok://join?code=\(gameId)") ?? URL(fileURLWithPath: ""),
                        subject: Text("Join Omok"),
                        message: Text("Join my game with code: \(gameId)")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 11))
                    }
                }

                Spacer()

                Text(statusText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }

            // Bottom row: both players
            HStack(spacing: 16) {
                playerBadge(for: .black)
                playerBadge(for: .white)
                Spacer()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray6))
    }

    private func playerBadge(for color: Stone) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color == .black ? Color.black : Color.white)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color.gray, lineWidth: 0.5))

            // Show user's own name if this is their seat
            if let myColor = mySeat, color == myColor, !myName.isEmpty {
                Text(myName)
                    .font(.caption2)
                    .lineLimit(1)
                    .fontWeight(.semibold)
            }
            // Show opponent's name from game state
            else if let seat = players[color], let name = seat.displayName, !name.isEmpty {
                Text(name)
                    .font(.caption2)
                    .lineLimit(1)
            }
            // Waiting for opponent
            else {
                Text("Waiting…")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview {
    let blackSeat = PlayerSeat(uid: "user1", joinedAt: 0, name: "Chester")
    let whiteSeat = PlayerSeat(uid: "user2", joinedAt: 0, name: "Mina")
    let emptyPlayersDict = [Stone: PlayerSeat]()
    let fullPlayersDict: [Stone: PlayerSeat] = [.black: blackSeat, .white: whiteSeat]

    VStack(spacing: 16) {
        GameStatusBar(gameId: "abc12", statusText: "Your turn", mySeat: .black, myName: "Chester", players: fullPlayersDict)
        GameStatusBar(gameId: "xyz99", statusText: "Chester's turn", mySeat: .white, myName: "Mina", players: fullPlayersDict)
        GameStatusBar(gameId: "test1", statusText: "Waiting for opponent", mySeat: .black, myName: "Chester", players: [:])
        GameStatusBar(gameId: "test2", statusText: "Spectating", mySeat: nil, myName: "Chester", players: emptyPlayersDict)
    }
}

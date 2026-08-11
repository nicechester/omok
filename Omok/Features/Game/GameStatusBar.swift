import SwiftUI

struct GameStatusBar: View {
    let gameId: String
    let statusText: String
    let mySeat: Stone?
    let myName: String
    let players: [Stone: PlayerSeat]
    let remainingSeconds: Int?

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

                HStack(spacing: 8) {
                    Text(statusText)
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    if let remainingSeconds {
                        Text("\(remainingSeconds)s")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(timerColor(remainingSeconds))
                    }
                }
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

    private func timerColor(_ seconds: Int) -> Color {
        if seconds <= 2 {
            return .red
        } else if seconds <= 4 {
            return .orange
        } else {
            return .primary
        }
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
            // Show opponent's name from game state, with disconnected status if inactive
            else if let seat = players[color], let name = seat.displayName, !name.isEmpty {
                if seat.active == false {
                    Text("\(name) (disconnected)")
                        .font(.caption2)
                        .lineLimit(1)
                        .foregroundColor(.gray)
                } else {
                    Text(name)
                        .font(.caption2)
                        .lineLimit(1)
                }
            }
            // Waiting for opponent (seat is empty)
            else {
                Text("Waiting…")
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
        }
    }
}

#Preview {
    let blackSeat = PlayerSeat(uid: "user1", joinedAt: 0, name: "Chester", active: true)
    let whiteSeat = PlayerSeat(uid: "user2", joinedAt: 0, name: "Mina", active: true)
    let emptyPlayersDict = [Stone: PlayerSeat]()
    let fullPlayersDict: [Stone: PlayerSeat] = [.black: blackSeat, .white: whiteSeat]

    VStack(spacing: 16) {
        GameStatusBar(gameId: "abc12", statusText: "Your turn", mySeat: .black, myName: "Chester", players: fullPlayersDict, remainingSeconds: nil)
        GameStatusBar(gameId: "xyz99", statusText: "Chester's turn", mySeat: .white, myName: "Mina", players: fullPlayersDict, remainingSeconds: 15)
        GameStatusBar(gameId: "test1", statusText: "Waiting for opponent", mySeat: .black, myName: "Chester", players: [:], remainingSeconds: nil)
        GameStatusBar(gameId: "test2", statusText: "Spectating", mySeat: nil, myName: "Chester", players: emptyPlayersDict, remainingSeconds: nil)
        GameStatusBar(gameId: "test3", statusText: "Your turn", mySeat: .black, myName: "Chester", players: fullPlayersDict, remainingSeconds: 3)
        GameStatusBar(gameId: "test4", statusText: "Opponent's turn", mySeat: .white, myName: "Mina", players: fullPlayersDict, remainingSeconds: 1)
    }
}

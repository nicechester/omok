import SwiftUI

struct GameStatusBar: View {
    let gameId: String
    let statusText: String
    let mySeat: Stone?
    let opponentName: String?

    @State private var showCopyFeedback = false

    var body: some View {
        HStack(spacing: 12) {
            // Room code and share
            VStack(alignment: .leading, spacing: 4) {
                Text("Room")
                    .font(.caption)
                    .foregroundColor(.gray)
                HStack(spacing: 8) {
                    Text(gameId)
                        .font(.title2)
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
                            .font(.system(size: 12))
                            .foregroundColor(showCopyFeedback ? .green : .blue)
                    }
                    ShareLink(
                        item: URL(string: "https://omok.example.com/?code=\(gameId)") ?? URL(fileURLWithPath: ""),
                        subject: Text("Join Omok"),
                        message: Text("Join my game with code: \(gameId)")
                    ) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12))
                    }
                }
            }

            Spacer()

            // Status text
            VStack(alignment: .trailing, spacing: 4) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.gray)
                Text(statusText)
                    .font(.headline)
                if let opponentName {
                    Text("vs \(opponentName)")
                        .font(.caption)
                        .foregroundColor(.gray)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            // Your color swatch
            if let mySeat = mySeat {
                VStack(alignment: .center, spacing: 4) {
                    Text("Your Color")
                        .font(.caption)
                        .foregroundColor(.gray)
                    Circle()
                        .fill(mySeat == .black ? Color.black : Color.white)
                        .frame(width: 20, height: 20)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 0.5))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6))
    }
}

#Preview {
    VStack {
        GameStatusBar(gameId: "abc12", statusText: "Your turn", mySeat: .black, opponentName: "Mina")
        GameStatusBar(gameId: "xyz99", statusText: "Chester's turn", mySeat: .white, opponentName: "Chester")
        GameStatusBar(gameId: "test1", statusText: "Spectating", mySeat: nil, opponentName: nil)
    }
}

import SwiftUI

struct ResultBanner: View {
    let result: GameResult?
    let isSpectator: Bool
    let isMyWin: Bool
    let didVoteRematch: Bool
    let onRematchTapped: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            // Result text
            if let result = result {
                Text(resultTitle(for: result))
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(resultColor(for: result))
            }

            // Rematch button (only for players, not spectators)
            if !isSpectator {
                Button(action: onRematchTapped) {
                    HStack {
                        Image(systemName: didVoteRematch ? "checkmark.circle.fill" : "arrow.clockwise")
                        Text(didVoteRematch ? "Waiting for opponent…" : "Rematch")
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(didVoteRematch ? Color.gray.opacity(0.3) : Color.blue)
                    .foregroundColor(didVoteRematch ? .gray : .white)
                    .cornerRadius(8)
                }
                .disabled(didVoteRematch)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(radius: 4)
        )
        .padding(.horizontal, 16)
    }

    private func resultTitle(for result: GameResult) -> String {
        if isSpectator {
            return "\(result.rawValue.capitalized) wins"
        } else {
            switch result {
            case .black, .white:
                return "You \(isMyWin ? "win" : "lose")"
            case .draw:
                return "Draw"
            }
        }
    }

    private func resultColor(for result: GameResult) -> Color {
        switch result {
        case .draw:
            return .gray
        case .black, .white:
            return (isSpectator || isMyWin) ? .green : .red
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ResultBanner(
            result: .black,
            isSpectator: false,
            isMyWin: true,
            didVoteRematch: false,
            onRematchTapped: {}
        )

        ResultBanner(
            result: .white,
            isSpectator: false,
            isMyWin: false,
            didVoteRematch: true,
            onRematchTapped: {}
        )

        ResultBanner(
            result: .draw,
            isSpectator: true,
            isMyWin: false,
            didVoteRematch: false,
            onRematchTapped: {}
        )
    }
    .padding()
}

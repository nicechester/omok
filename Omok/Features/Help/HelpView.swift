import SwiftUI

struct HelpView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("How to Play")
                                .font(.headline)
                            Text("Omok (오목) is a strategy board game where two players take turns placing stones on a 15×15 board. The first player to get 5 stones in a row (horizontally, vertically, or diagonally) wins the game.")
                                .font(.body)

                            BoardDiagram()
                                .frame(height: 150)
                                .padding(.vertical, 8)
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Game Rules")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                RuleRow(title: "Board Size", description: "15×15 intersection board")
                                RuleRow(title: "Players", description: "Two players (Black and White)")
                                RuleRow(title: "Starting Move", description: "Black always goes first")
                                RuleRow(title: "Win Condition", description: "Exactly 5 stones in a row (overlines don't count)")
                                RuleRow(title: "Draw", description: "Board fills up with no winner")
                                RuleRow(title: "Alternating Turns", description: "Players take turns placing one stone per turn")
                            }

                            Divider()
                                .padding(.vertical, 8)

                            WinConditionExample()
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Game Modes")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                ModeRow(title: "vs Player", description: "Play against another person online")
                                ModeRow(title: "vs AI", description: "Play against the computer (Easy, Normal, Hard)")
                            }
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Features")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                FeatureRow(title: "Undo", description: "Take back your last move")
                                FeatureRow(title: "Timer", description: "Optional turn timer for faster games")
                                FeatureRow(title: "Rematch", description: "Play again with the same opponent")
                                FeatureRow(title: "Player Names", description: "Set and see player nicknames")
                                FeatureRow(title: "Turn Indicator", description: "See whose turn it is at a glance")
                            }
                        }
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Tips")
                                .font(.headline)
                            VStack(alignment: .leading, spacing: 8) {
                                TipRow(tip: "Control the center of the board for strategic advantage")
                                TipRow(tip: "Block your opponent's winning moves while building your own")
                                TipRow(tip: "An open three (3 in a row with empty space on both ends) is valuable")
                                TipRow(tip: "Play against different AI difficulties to improve your skills")
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("How to Play")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

struct RuleRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct ModeRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct FeatureRow: View {
    let title: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.semibold)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct TipRow: View {
    let tip: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
                .font(.caption)
            Text(tip)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

struct BoardDiagram: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { col in
                    ZStack {
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        Circle()
                            .fill(
                                col == 2 ? Color.black :
                                col == 3 ? Color.white :
                                Color.clear
                            )
                            .padding(4)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { col in
                    ZStack {
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    }
                }
            }
            HStack(spacing: 0) {
                ForEach(0..<5, id: \.self) { _ in
                    ZStack {
                        Rectangle()
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .background(Color.gray.opacity(0.05))
    }
}

struct WinConditionExample: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("5 in a Row = Win")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 4) {
                ForEach(0..<5, id: \.self) { _ in
                    Circle()
                        .fill(Color.black)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.vertical, 4)

            Text("6 in a Row = No Win (Overline)")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack(spacing: 4) {
                ForEach(0..<6, id: \.self) { _ in
                    Circle()
                        .fill(Color.gray)
                        .frame(width: 20, height: 20)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

#Preview {
    HelpView()
}

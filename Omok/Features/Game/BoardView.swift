import SwiftUI

struct BoardView: View {
    let gameState: GameState?
    let canPlay: Bool
    let onTap: (Cell) -> Void

    var body: some View {
        GeometryReader { geometry in
            Canvas { context, size in
                let side = min(size.width, size.height)
                let cell = side / 15

                // Draw wooden background
                let backgroundPath = Path(roundedRect: CGRect(origin: .zero, size: CGSize(width: side, height: side)), cornerRadius: 0)
                context.fill(backgroundPath, with: .color(Color(red: 0.87, green: 0.72, blue: 0.47)))

                // Draw grid lines
                var gridPath = Path()
                for i in 0..<15 {
                    let pos = cell / 2 + CGFloat(i) * cell
                    gridPath.move(to: CGPoint(x: pos, y: cell / 2))
                    gridPath.addLine(to: CGPoint(x: pos, y: cell / 2 + 14 * cell))
                    gridPath.move(to: CGPoint(x: cell / 2, y: pos))
                    gridPath.addLine(to: CGPoint(x: cell / 2 + 14 * cell, y: pos))
                }
                context.stroke(gridPath, with: .color(.black), lineWidth: 0.5)

                // Draw star points
                let starPositions = [3, 7, 11]
                for r in starPositions {
                    for c in starPositions {
                        let x = cell / 2 + CGFloat(c) * cell
                        let y = cell / 2 + CGFloat(r) * cell
                        let starPath = Path(ellipseIn: CGRect(x: x - 2, y: y - 2, width: 4, height: 4))
                        context.fill(starPath, with: .color(.black))
                    }
                }

                // Draw stones
                if let game = gameState {
                    let stoneRadius = cell * 0.42
                    for (boardCell, stone) in game.board {
                        let x = cell / 2 + CGFloat(boardCell.c) * cell
                        let y = cell / 2 + CGFloat(boardCell.r) * cell
                        let stonePath = Path(ellipseIn: CGRect(x: x - stoneRadius, y: y - stoneRadius, width: stoneRadius * 2, height: stoneRadius * 2))

                        if stone == .black {
                            context.fill(stonePath, with: .color(.black))
                        } else {
                            context.fill(stonePath, with: .color(.white))
                            context.stroke(stonePath, with: .color(.gray), lineWidth: 0.5)
                        }
                    }

                    // Draw last move marker
                    if let lastMove = game.lastMove {
                        let x = cell / 2 + CGFloat(lastMove.c) * cell
                        let y = cell / 2 + CGFloat(lastMove.r) * cell
                        let markerPath = Path(ellipseIn: CGRect(x: x - 3, y: y - 3, width: 6, height: 6))
                        context.stroke(markerPath, with: .color(.red), lineWidth: 1)
                    }

                    // Draw winning line highlight
                    if let winningLine = game.winningLine {
                        for winCell in winningLine {
                            let x = cell / 2 + CGFloat(winCell.c) * cell
                            let y = cell / 2 + CGFloat(winCell.r) * cell
                            let ringRadius = cell * 0.5
                            let ringPath = Path(ellipseIn: CGRect(x: x - ringRadius, y: y - ringRadius, width: ringRadius * 2, height: ringRadius * 2))
                            context.stroke(ringPath, with: .color(.green), lineWidth: 1.5)
                        }
                    }
                }
            }
            .aspectRatio(1, contentMode: .fit)
            .contentShape(Rectangle())
            .onTapGesture { tapPoint in
                guard canPlay else { return }
                let side = min(geometry.size.width, geometry.size.height)
                let cell = side / 15

                let c = Int(((tapPoint.x - cell / 2) / cell).rounded())
                let r = Int(((tapPoint.y - cell / 2) / cell).rounded())

                guard (0..<15).contains(c) && (0..<15).contains(r) else { return }

                let intersectionX = cell / 2 + CGFloat(c) * cell
                let intersectionY = cell / 2 + CGFloat(r) * cell
                let distance = hypot(tapPoint.x - intersectionX, tapPoint.y - intersectionY)

                guard distance <= cell * 0.5 else { return }

                let tappedCell = Cell(r: r, c: c)
                onTap(tappedCell)
            }
        }
    }
}

#Preview {
    var board: [Cell: Stone] = [:]
    board[Cell(r: 7, c: 7)] = .black
    board[Cell(r: 7, c: 8)] = .white
    board[Cell(r: 8, c: 7)] = .black
    board[Cell(r: 8, c: 8)] = .white

    let state = GameState(
        status: .playing,
        turn: .black,
        round: 0,
        moveCount: 4,
        board: board,
        lastMove: LastMove(r: 8, c: 8, color: .white),
        result: nil,
        winningLine: nil,
        players: [
            .black: PlayerSeat(uid: "user1", joinedAt: 0, name: "Chester"),
            .white: PlayerSeat(uid: "user2", joinedAt: 0, name: "Mina")
        ],
        rematchVotes: [],
        createdBy: "user1",
        speaking: [:]
    )

    BoardView(
        gameState: state,
        canPlay: true,
        onTap: { cell in print("Tapped: \(cell)") }
    )
}

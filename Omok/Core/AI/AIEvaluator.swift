import Foundation

enum AIEvaluator {
    private static let scoreFour: Int = 50_000
    private static let scoreThree: Int = 1_000
    private static let scoreTwo: Int = 100
    private static let scoreOne: Int = 10

    static func evaluate(board: [Cell: Stone], aiColor: Stone, moveCount: Int) -> Int {
        var aiScore = 0
        var opponentScore = 0
        let opponentColor = aiColor.opposite
        let directions: [(dr: Int, dc: Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

        for r in 0..<GomokuRules.size {
            for c in 0..<GomokuRules.size {
                let cell = Cell(r: r, c: c)
                for dir in directions {
                    aiScore += scoreForLine(from: cell, dir: dir, color: aiColor, board: board)
                    opponentScore += scoreForLine(from: cell, dir: dir, color: opponentColor, board: board)
                }
            }
        }

        return aiScore - opponentScore * 2
    }

    /// Score a window of 5 cells starting at `cell` in `dir` for `color`.
    /// Uses a sliding window of 5 so gaps (e.g. XX_XX) are naturally handled.
    static func scoreWindow(from cell: Cell, dir: (dr: Int, dc: Int), color: Stone, board: [Cell: Stone]) -> Int {
        // Check all windows of 5 that include this cell
        var total = 0
        for offset in 0..<5 {
            let start = Cell(r: cell.r - dir.dr * offset, c: cell.c - dir.dc * offset)
            total += scoreForLine(from: start, dir: dir, color: color, board: board)
        }
        return total
    }

    private static func scoreForLine(from cell: Cell, dir: (dr: Int, dc: Int), color: Stone, board: [Cell: Stone]) -> Int {
        // Collect up to 5 cells, stopping at board edge
        var cells: [Cell] = []
        var cur = cell
        for _ in 0..<5 {
            guard GomokuRules.isValid(cell: cur) else { break }
            cells.append(cur)
            cur = Cell(r: cur.r + dir.dr, c: cur.c + dir.dc)
        }

        // Count friendly and enemy stones in the window
        var friendly = 0
        var enemy = 0
        for c in cells {
            if board[c] == color { friendly += 1 }
            else if board[c] != nil { enemy += 1 }
        }

        // Window is blocked by enemy — no value
        if enemy > 0 { return 0 }

        switch friendly {
        case 4: return scoreFour
        case 3: return scoreThree
        case 2: return scoreTwo
        case 1: return scoreOne
        default: return 0
        }
    }
}

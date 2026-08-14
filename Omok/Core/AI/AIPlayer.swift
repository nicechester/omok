import Foundation

actor AIPlayer {
    let difficulty: AIDifficulty
    let aiColor: Stone
    let playerColor: Stone

    init(difficulty: AIDifficulty, aiColor: Stone) {
        self.difficulty = difficulty
        self.aiColor = aiColor
        self.playerColor = aiColor.opposite
    }

    /// Search for the best move using minimax with iterative deepening.
    /// Returns the best cell to play, or nil if no valid move found.
    func findBestMove(board: [Cell: Stone], moveCount: Int) async -> Cell? {
        let deadline = Date().addingTimeInterval(difficulty.timeLimit)
        var bestMove: Cell?
        var bestValue = -10_000_000

        // Generate candidate moves
        let candidates = generateCandidates(board: board, moveCount: moveCount)
        if candidates.isEmpty {
            return nil
        }

        // Iterative deepening: increase depth from 1 to maxDepth
        for depth in 1...difficulty.maxDepth {
            if Date() >= deadline {
                break  // Time budget exceeded
            }

            var depthBestMove: Cell?
            var depthBestValue = -10_000_000

            // Evaluate all candidates at this depth
            for candidate in candidates {
                if Date() >= deadline {
                    break  // Deadline exceeded mid-iteration
                }

                var testBoard = board
                testBoard[candidate] = aiColor

                let value = minimax(board: testBoard, lastMove: candidate, depth: depth - 1, isMaximizing: false, alpha: -10_000_000, beta: 10_000_000, deadline: deadline)

                if value > depthBestValue {
                    depthBestValue = value
                    depthBestMove = candidate
                }
            }

            // Only accept this depth's result if completed before deadline
            if Date() < deadline, let move = depthBestMove {
                bestMove = move
                bestValue = depthBestValue
            }
        }

        return bestMove
    }

    /// Minimax with alpha-beta pruning.
    /// Returns the score for the current position.
    private func minimax(
        board: [Cell: Stone],
        lastMove: Cell,
        depth: Int,
        isMaximizing: Bool,
        alpha: Int,
        beta: Int,
        deadline: Date
    ) -> Int {
        // The last move was made by the player whose turn it no longer is.
        // isMaximizing=true means it's now AI's turn, so opponent just moved.
        // isMaximizing=false means it's now opponent's turn, so AI just moved.
        let lastMoveColor = isMaximizing ? playerColor : aiColor
        if let _ = GomokuRules.winningLine(board: board, from: lastMove, color: lastMoveColor) {
            // AI won → positive, opponent won → negative. Prefer faster wins/slower losses.
            let score = 10_000_000 + depth
            return isMaximizing ? -score : score
        }

        if depth == 0 || GomokuRules.isBoardFull(moveCount: board.count) {
            return AIEvaluator.evaluate(board: board, aiColor: aiColor, moveCount: board.count)
        }

        var alpha = alpha
        var beta = beta

        if isMaximizing {
            // AI's turn: maximize score
            var maxEval = -10_000_000
            let candidates = generateCandidates(board: board, moveCount: board.count)

            for candidate in candidates {
                if Date() >= deadline {
                    break  // Time limit exceeded, bail out
                }

                var newBoard = board
                newBoard[candidate] = aiColor
                let eval = minimax(board: newBoard, lastMove: candidate, depth: depth - 1, isMaximizing: false, alpha: alpha, beta: beta, deadline: deadline)
                maxEval = max(maxEval, eval)
                alpha = max(alpha, eval)
                if beta <= alpha {
                    break  // Beta cutoff
                }
            }
            return maxEval
        } else {
            // Opponent's turn: minimize score
            var minEval = 10_000_000
            let candidates = generateCandidates(board: board, moveCount: board.count)

            for candidate in candidates {
                if Date() >= deadline {
                    break  // Time limit exceeded, bail out
                }

                var newBoard = board
                newBoard[candidate] = playerColor
                let eval = minimax(board: newBoard, lastMove: candidate, depth: depth - 1, isMaximizing: true, alpha: alpha, beta: beta, deadline: deadline)
                minEval = min(minEval, eval)
                beta = min(beta, eval)
                if beta <= alpha {
                    break  // Alpha cutoff
                }
            }
            return minEval
        }
    }

    /// Generate candidate moves by finding cells near existing stones.
    /// Also filters out 3x3 rule violations.
    private func generateCandidates(board: [Cell: Stone], moveCount: Int) -> [Cell] {
        var candidates: Set<Cell> = []
        var candidateList: [Cell] = []

        // If board is empty, play center
        if board.isEmpty {
            return [Cell(r: 7, c: 7)]
        }

        // Find all cells adjacent to existing stones
        for (cell, _) in board {
            for dr in -2...2 {
                for dc in -2...2 {
                    let candidate = Cell(r: cell.r + dr, c: cell.c + dc)
                    if GomokuRules.isValid(cell: candidate), board[candidate] == nil {
                        candidates.insert(candidate)
                    }
                }
            }
        }

        // Filter candidates: remove 3x3 violations
        for candidate in candidates {
            var testBoard = board
            testBoard[candidate] = aiColor

            // Check if placing at this candidate creates two open threes
            let openThrees = GomokuRules.countOpenThrees(board: testBoard, from: candidate, color: aiColor)
            if openThrees < 2 {
                candidateList.append(candidate)
            }
        }

        // Sort by heuristic: prioritize cells near the center and near multiple stones
        candidateList.sort { a, b in
            let scoreA = heuristicScore(cell: a, board: board)
            let scoreB = heuristicScore(cell: b, board: board)
            return scoreA > scoreB
        }

        // Limit candidates to top N
        return Array(candidateList.prefix(20))
    }

    /// Score a candidate cell based on proximity to existing stones and board position.
    private func heuristicScore(cell: Cell, board: [Cell: Stone]) -> Int {
        var score = 0
        let directions: [(dr: Int, dc: Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

        // Score the threat this cell creates for AI (offense)
        var aiBoard = board
        aiBoard[cell] = aiColor
        for dir in directions {
            score += AIEvaluator.scoreWindow(from: cell, dir: dir, color: aiColor, board: aiBoard)
        }

        // Score the threat this cell blocks for opponent (defense), weighted higher
        var opponentBoard = board
        opponentBoard[cell] = playerColor
        for dir in directions {
            score += AIEvaluator.scoreWindow(from: cell, dir: dir, color: playerColor, board: opponentBoard) * 2
        }

        return score
    }
}

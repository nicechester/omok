import Foundation

/// Pure gomoku (five-in-a-row) rules. No Firebase dependency so it can run
/// synchronously inside an RTDB transaction body, where re-execution on retry
/// is mandatory.
enum GomokuRules {
    static let size = 15

    static func isValid(cell: Cell) -> Bool {
        (0..<size).contains(cell.r) && (0..<size).contains(cell.c)
    }

    static func isBoardFull(moveCount: Int) -> Bool {
        moveCount >= size * size
    }

    /// Count open threes created by placing a stone at `cell`.
    /// An open three is exactly 3 consecutive stones with empty space on both ends,
    /// AND no additional same-color stones beyond a single gap (which would make it a four).
    /// Returns the number of open threes created (0, 1, or 2).
    /// Winning move (5+) overrides this rule and should be checked first.
    static func countOpenThrees(board: [Cell: Stone], from cell: Cell, color: Stone) -> Int {
        let directions: [(dr: Int, dc: Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]
        var openThreeCount = 0

        for direction in directions {
            var forward = Cell(r: cell.r + direction.dr, c: cell.c + direction.dc)
            var forwardCount = 0
            while isValid(cell: forward), board[forward] == color {
                forwardCount += 1
                forward = Cell(r: forward.r + direction.dr, c: forward.c + direction.dc)
            }
            let forwardEmpty = isValid(cell: forward) && board[forward] == nil
            
            // Check for stone beyond the gap (e.g., OOO_O pattern)
            var forwardGapStone = false
            if forwardEmpty {
                let beyondGap = Cell(r: forward.r + direction.dr, c: forward.c + direction.dc)
                if isValid(cell: beyondGap), board[beyondGap] == color {
                    forwardGapStone = true
                }
            }

            var backward = Cell(r: cell.r - direction.dr, c: cell.c - direction.dc)
            var backwardCount = 0
            while isValid(cell: backward), board[backward] == color {
                backwardCount += 1
                backward = Cell(r: backward.r - direction.dr, c: backward.c - direction.dc)
            }
            let backwardEmpty = isValid(cell: backward) && board[backward] == nil
            
            // Check for stone beyond the gap
            var backwardGapStone = false
            if backwardEmpty {
                let beyondGap = Cell(r: backward.r - direction.dr, c: backward.c - direction.dc)
                if isValid(cell: beyondGap), board[beyondGap] == color {
                    backwardGapStone = true
                }
            }

            // Total consecutive stones including the placed stone
            let totalConsecutive = forwardCount + 1 + backwardCount

            // Open three: exactly 3 consecutive stones with empty on both sides,
            // but NOT if there's a same-color stone beyond the gap (making it 4+)
            if totalConsecutive == 3 && forwardEmpty && backwardEmpty && !forwardGapStone && !backwardGapStone {
                openThreeCount += 1
            }
        }

        return openThreeCount
    }

    /// Convention: `cell` must already be present in `board` as `color` (the
    /// caller writes the just-placed stone into `board` *before* calling this).
    ///
    /// Checks the 4 axes through `cell` (horizontal, vertical, and both
    /// diagonals), walking outward in both directions on each axis and
    /// counting contiguous same-color stones. Free-style rules: any run of 5
    /// or more wins (overlines of 6+ are not excluded). Returns the full
    /// contiguous run's cells for the first axis that reaches >= 5, or nil if
    /// no axis does. Only the placed cell is examined, so this is O(1) per
    /// move rather than a full-board scan.
    static func winningLine(board: [Cell: Stone], from cell: Cell, color: Stone) -> [Cell]? {
        let directions: [(dr: Int, dc: Int)] = [(0, 1), (1, 0), (1, 1), (1, -1)]

        for direction in directions {
            var line: [Cell] = [cell]

            var forward = Cell(r: cell.r + direction.dr, c: cell.c + direction.dc)
            while isValid(cell: forward), board[forward] == color {
                line.append(forward)
                forward = Cell(r: forward.r + direction.dr, c: forward.c + direction.dc)
            }

            var backward = Cell(r: cell.r - direction.dr, c: cell.c - direction.dc)
            while isValid(cell: backward), board[backward] == color {
                line.append(backward)
                backward = Cell(r: backward.r - direction.dr, c: backward.c - direction.dc)
            }

            if line.count >= 5 {
                return line
            }
        }

        return nil
    }
}

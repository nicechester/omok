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

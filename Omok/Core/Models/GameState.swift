import Foundation

enum GameStatus: String, Codable, Sendable {
    case waiting
    case playing
    case finished
}

enum GameResult: String, Codable, Sendable {
    case black
    case white
    case draw
}

struct PlayerSeat: Codable, Sendable {
    let uid: String
    let color: Stone
    let joinedAt: Int
    let name: String?
    let active: Bool?

    var displayName: String? {
        let sanitized = PlayerName.sanitize(name ?? "")
        return sanitized.isEmpty ? nil : sanitized
    }
}

struct LastMove: Codable, Sendable {
    let r: Int
    let c: Int
    let color: Stone

    var cell: Cell {
        Cell(r: r, c: c)
    }
}

struct UndoRequest: Codable, Sendable {
    let requestedBy: String
    let createdAt: Int
}

struct Reaction: Sendable {
    let from: String
    let emoji: String
    let timestamp: Int
}

struct GameState: Sendable {
    let status: GameStatus
    let turn: Stone
    let round: Int
    let moveCount: Int
    let board: [Cell: Stone]
    let lastMove: LastMove?
    let result: GameResult?
    let winningLine: [Cell]?
    let players: [Stone: PlayerSeat]
    let rematchVotes: Set<String>
    let undoRequest: UndoRequest?
    let previousLastMove: LastMove?
    let createdBy: String
    let speaking: [Stone: Bool]
    let timerDuration: Int?
    let turnStartedAt: Int?
    let scores: [String: Int]
    let reaction: Reaction?

    func seat(of uid: String) -> Stone? {
        for (color, seat) in players {
            if seat.uid == uid {
                return color
            }
        }
        return nil
    }
}

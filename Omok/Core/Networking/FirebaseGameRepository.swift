import Foundation
import FirebaseDatabase
import os.log

private let logger = Logger(subsystem: "io.github.nicechester.omok", category: "Firebase")

final class FirebaseGameRepository: GameRepository {
    private let database: DatabaseReference

    init(database: DatabaseReference = Database.database().reference()) {
        self.database = database
    }

    private func gameRef(_ gameId: String) -> DatabaseReference {
        database.child("omok/games").child(gameId)
    }

    // MARK: - Listen

    func listenToGame(gameId: String) -> AsyncStream<GameState?> {
        AsyncStream { continuation in
            let ref = gameRef(gameId)

            let handle = ref.observe(.value) { snapshot in
                continuation.yield(Self.decodeGameState(from: snapshot))
            } withCancel: { error in
                logger.error("listenToGame(\(gameId)) cancelled: \(error.localizedDescription)")
                continuation.finish()
            }

            continuation.onTermination = { _ in
                ref.removeObserver(withHandle: handle)
            }
        }
    }

    // MARK: - Fetch (one-shot, read-only)

    func fetchGame(gameId: String) async throws -> GameState? {
        let snapshot = try await gameRef(gameId).getData()
        return Self.decodeGameState(from: snapshot)
    }

    // MARK: - Create

    func createGame(gameId: String, creatorUid: String, creatorName: String, timerDuration: Int?) async throws {
        let sanitizedName = PlayerName.sanitize(creatorName)
        var blackSeat: [String: Any] = [
            "uid": creatorUid,
            "joinedAt": ServerValue.timestamp(),
            "active": true
        ]
        if !sanitizedName.isEmpty {
            blackSeat["name"] = sanitizedName
        }
        var data: [String: Any] = [
            "status": GameStatus.waiting.rawValue,
            "turn": Stone.black.rawValue,
            "round": 0,
            "moveCount": 0,
            "players": [
                "black": blackSeat
            ],
            "speaking": [:],
            "scores": [:],
            "createdBy": creatorUid,
            "createdAt": ServerValue.timestamp(),
            "updatedAt": ServerValue.timestamp()
        ]
        if let duration = timerDuration {
            data["timerDuration"] = duration
            data["turnStartedAt"] = ServerValue.timestamp()
        }
        do {
            try await gameRef(gameId).setValue(data)
            logger.info("Game created: \(gameId)")
        } catch {
            logger.error("Failed to create game \(gameId): \(error.localizedDescription)")
            throw error
        }
    }

    // MARK: - Claim seat

    func claimSeat(gameId: String, uid: String, name: String) async throws -> Stone {
        let ref = gameRef(gameId)
        let sanitizedName = PlayerName.sanitize(name)

        // Fetch current game state
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        let players = dict["players"] as? [String: Any] ?? [:]

        // Check if already seated
        for color in [Stone.black, Stone.white] {
            if let seat = players[color.rawValue] as? [String: Any],
               seat["uid"] as? String == uid {
                // Already seated, update name if needed
                let existingName = seat["name"] as? String ?? ""
                if existingName != sanitizedName, !sanitizedName.isEmpty {
                    try await ref.child("players/\(color.rawValue)/name").setValue(sanitizedName)
                    try await ref.child("updatedAt").setValue(ServerValue.timestamp())
                }
                return color
            }
        }

        // Find empty seat
        let blackTaken = players[Stone.black.rawValue] != nil
        let whiteTaken = players[Stone.white.rawValue] != nil

        guard !(blackTaken && whiteTaken) else {
            throw GameError.gameFull
        }

        let seatColor: Stone = blackTaken ? .white : .black
        var newSeat: [String: Any] = [
            "uid": uid,
            "joinedAt": ServerValue.timestamp(),
            "active": true
        ]
        if !sanitizedName.isEmpty {
            newSeat["name"] = sanitizedName
        }

        // Write seat and update status if both players present
        var updates: [String: Any] = [
            "players/\(seatColor.rawValue)": newSeat,
            "updatedAt": ServerValue.timestamp()
        ]
        if blackTaken || seatColor == .black {
            // Other seat was taken or we're taking black, so after this write both are filled
            if blackTaken && seatColor == .white {
                updates["status"] = GameStatus.playing.rawValue
            }
        }

        try await ref.updateChildValues(updates)
        return seatColor
    }

    // MARK: - Place stone

    func placeStone(gameId: String, at cell: Cell, uid: String) async throws {
        guard GomokuRules.isValid(cell: cell) else {
            throw GameError.cellOccupied
        }

        let ref = gameRef(gameId)

        // Fetch current state
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard let statusRaw = dict["status"] as? String,
              statusRaw == GameStatus.playing.rawValue else {
            throw GameError.gameNotActive
        }

        guard let turnRaw = dict["turn"] as? String,
              let turn = Stone(rawValue: turnRaw) else {
            throw GameError.gameNotActive
        }

        guard let players = dict["players"] as? [String: Any],
              let seatDict = players[turn.rawValue] as? [String: Any],
              seatDict["uid"] as? String == uid else {
            throw GameError.notYourTurn
        }

        // Prevent move if undo request is pending
        if dict["undoRequest"] != nil {
            throw GameError.gameNotActive
        }

        let board = dict["board"] as? [String: Any] ?? [:]
        let key = cell.key
        guard board[key] == nil else {
            throw GameError.cellOccupied
        }

        // Build current board for win detection
        var boardCells: [Cell: Stone] = [:]
        for (boardKey, boardValue) in board {
            if let boardCell = Cell(key: boardKey),
               let stoneRaw = boardValue as? String,
               let stone = Stone(rawValue: stoneRaw) {
                boardCells[boardCell] = stone
            }
        }
        boardCells[cell] = turn

        let moveCount = (dict["moveCount"] as? Int ?? 0) + 1

        // Capture previousLastMove before updating lastMove
        var updates: [String: Any] = [
            "board/\(key)": turn.rawValue,
            "moveCount": moveCount,
            "lastMove": ["r": cell.r, "c": cell.c, "color": turn.rawValue],
            "turn": turn.opposite.rawValue,
            "updatedAt": ServerValue.timestamp()
        ]

        // Re-stamp turnStartedAt if timer is enabled
        if dict["timerDuration"] != nil {
            updates["turnStartedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        }

        // Store previousLastMove for undo functionality
        if let lastMoveDict = dict["lastMove"] as? [String: Any] {
            updates["previousLastMove"] = lastMoveDict
        } else {
            updates["previousLastMove"] = NSNull()
        }

        // Check for win and increment score
        if let line = GomokuRules.winningLine(board: boardCells, from: cell, color: turn) {
            updates["status"] = GameStatus.finished.rawValue
            updates["result"] = turn.rawValue
            updates["winningLine"] = line.map { ["r": $0.r, "c": $0.c] }
            // Increment winner's score
            if let winnerUid = seatDict["uid"] as? String {
                let currentScore = (dict["scores"] as? [String: Any])?[winnerUid] as? Int ?? 0
                updates["scores/\(winnerUid)"] = currentScore + 1
            }
        } else if GomokuRules.isBoardFull(moveCount: moveCount) {
            updates["status"] = GameStatus.finished.rawValue
            updates["result"] = GameResult.draw.rawValue
        }

        try await ref.updateChildValues(updates)
    }
    
    // MARK: - Forfeit

    func forfeit(gameId: String, uid: String) async throws {
        let ref = gameRef(gameId)

        // Fetch current state
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard let statusRaw = dict["status"] as? String,
              statusRaw == GameStatus.playing.rawValue else {
            throw GameError.gameNotActive
        }

        guard let players = dict["players"] as? [String: Any] else {
            throw GameError.gameNotFound
        }

        // Find which seat the user has
        var userSeat: Stone?
        var winnerUid: String?
        for color in [Stone.black, Stone.white] {
            if let seat = players[color.rawValue] as? [String: Any],
               seat["uid"] as? String == uid {
                userSeat = color
            } else if let seat = players[color.rawValue] as? [String: Any],
                      let uid = seat["uid"] as? String {
                winnerUid = uid
            }
        }

        guard let forfeitingSeat = userSeat else {
            throw GameError.notYourTurn
        }

        // Winner is the opponent
        let winner = forfeitingSeat.opposite

        var updates: [String: Any] = [
            "status": GameStatus.finished.rawValue,
            "result": winner.rawValue,
            "undoRequest": NSNull(),
            "updatedAt": ServerValue.timestamp()
        ]

        // Increment winner's score
        if let winnerUid {
            let currentScore = (dict["scores"] as? [String: Any])?[winnerUid] as? Int ?? 0
            updates["scores/\(winnerUid)"] = currentScore + 1
        }

        try await ref.updateChildValues(updates)
    }

    // MARK: - Delete

    func deleteGame(gameId: String, uid: String) async throws {
        let ref = gameRef(gameId)
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        let createdBy = dict["createdBy"] as? String
        let players = dict["players"] as? [String: Any] ?? [:]
        let isSeated = [Stone.black, Stone.white].contains { color in
            (players[color.rawValue] as? [String: Any])?["uid"] as? String == uid
        }
        guard createdBy == uid || isSeated else {
            throw GameError.deleteNotAllowed
        }

        try await ref.removeValue()
    }

    // MARK: - Rematch

    func voteRematch(gameId: String, uid: String) async throws {
        try await gameRef(gameId).child("rematch").child(uid).setValue(true)
    }

    func resetForRematch(gameId: String) async throws {
        let ref = gameRef(gameId)

        // Fetch current state to get round
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard let statusRaw = dict["status"] as? String,
              statusRaw == GameStatus.finished.rawValue else {
            // Already reset by other client, ignore
            return
        }

        let round = (dict["round"] as? Int ?? 0) + 1

        var updates: [String: Any] = [
            "round": round,
            "moveCount": 0,
            "board": NSNull(),
            "lastMove": NSNull(),
            "previousLastMove": NSNull(),
            "result": NSNull(),
            "winningLine": NSNull(),
            "rematch": NSNull(),
            "undoRequest": NSNull(),
            "turn": (round % 2 == 0 ? Stone.black : Stone.white).rawValue,
            "status": GameStatus.playing.rawValue,
            "updatedAt": ServerValue.timestamp()
        ]

        // Re-stamp turnStartedAt if timer is enabled (critical for round 2)
        if dict["timerDuration"] != nil {
            updates["turnStartedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        }

        try await ref.updateChildValues(updates)
    }

    // MARK: - Speaking

    func updateSpeaking(gameId: String, uid: String, isSpeaking: Bool) async throws {
        let ref = gameRef(gameId)

        // Fetch current state to get user's seat
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        let players = dict["players"] as? [String: Any] ?? [:]

        // Find user's seat
        var userSeat: Stone?
        for color in [Stone.black, Stone.white] {
            if let seat = players[color.rawValue] as? [String: Any],
               seat["uid"] as? String == uid {
                userSeat = color
                break
            }
        }

        guard let seat = userSeat else {
            throw GameError.gameNotFound
        }

        // Update speaking state for this player
        let updates: [String: Any] = [
            "speaking/\(seat.rawValue)": isSpeaking,
            "updatedAt": ServerValue.timestamp()
        ]

        try await ref.updateChildValues(updates)
    }

    func updatePlayerActive(gameId: String, uid: String, isActive: Bool) async throws {
        let ref = gameRef(gameId)

        // Fetch current state to get user's seat
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        let players = dict["players"] as? [String: Any] ?? [:]

        // Find user's seat
        var userSeat: Stone?
        for color in [Stone.black, Stone.white] {
            if let seat = players[color.rawValue] as? [String: Any],
               seat["uid"] as? String == uid {
                userSeat = color
                break
            }
        }

        guard let seat = userSeat else {
            throw GameError.gameNotFound
        }

        // Update active status for this player
        let updates: [String: Any] = [
            "players/\(seat.rawValue)/active": isActive,
            "updatedAt": ServerValue.timestamp()
        ]

        try await ref.updateChildValues(updates)
    }

    // MARK: - Undo

    func requestUndo(gameId: String, uid: String) async throws {
        let ref = gameRef(gameId)

        // Fetch current state
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard let statusRaw = dict["status"] as? String,
              statusRaw == GameStatus.playing.rawValue else {
            throw GameError.gameNotActive
        }

        let moveCount = dict["moveCount"] as? Int ?? 0
        guard moveCount >= 2 else {
            throw GameError.undoNotAllowed
        }

        guard dict["undoRequest"] == nil else {
            throw GameError.undoAlreadyPending
        }

        let updates: [String: Any] = [
            "undoRequest": ["requestedBy": uid, "createdAt": Int(Date().timeIntervalSince1970 * 1000)],
            "updatedAt": ServerValue.timestamp()
        ]

        try await ref.updateChildValues(updates)
    }

    func approveUndo(gameId: String, uid: String) async throws {
        let ref = gameRef(gameId)

        // Fetch current state
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard let statusRaw = dict["status"] as? String,
              statusRaw == GameStatus.playing.rawValue else {
            throw GameError.gameNotActive
        }

        guard let undoRequestDict = dict["undoRequest"] as? [String: Any],
              let requestedBy = undoRequestDict["requestedBy"] as? String else {
            throw GameError.noUndoPending
        }

        // The approving player must be the opponent of the requester
        guard let players = dict["players"] as? [String: Any] else {
            throw GameError.gameNotFound
        }

        var approverSeat: Stone?
        for color in [Stone.black, Stone.white] {
            if let seat = players[color.rawValue] as? [String: Any],
               seat["uid"] as? String == uid {
                approverSeat = color
                break
            }
        }

        guard let approverSeat else {
            throw GameError.gameNotFound
        }

        // Verify the approver is not the requester
        var requesterSeat: Stone?
        for color in [Stone.black, Stone.white] {
            if let seat = players[color.rawValue] as? [String: Any],
               seat["uid"] as? String == requestedBy {
                requesterSeat = color
                break
            }
        }
        guard let requesterSeat, requesterSeat != approverSeat else {
            throw GameError.notYourTurn
        }

        let moveCount = (dict["moveCount"] as? Int ?? 0) - 1
        let lastTurn = (dict["turn"] as? String).flatMap(Stone.init(rawValue:)) ?? .black

        var updates: [String: Any] = [
            "moveCount": moveCount,
            "turn": lastTurn.opposite.rawValue,
            "undoRequest": NSNull(),
            "updatedAt": ServerValue.timestamp()
        ]

        // Re-stamp turnStartedAt if timer is enabled (approval resets timer)
        if dict["timerDuration"] != nil {
            updates["turnStartedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        }

        // Revert board by removing the last stone
        if let lastMoveDict = dict["lastMove"] as? [String: Any],
           let r = lastMoveDict["r"] as? Int,
           let c = lastMoveDict["c"] as? Int {
            let cellKey = "\(r)_\(c)"
            updates["board/\(cellKey)"] = NSNull()
        }

        // Restore lastMove from previousLastMove
        if let previousLastMoveDict = dict["previousLastMove"] as? [String: Any] {
            updates["lastMove"] = previousLastMoveDict
        } else {
            updates["lastMove"] = NSNull()
        }

        updates["previousLastMove"] = NSNull()

        try await ref.updateChildValues(updates)
    }

    func rejectUndo(gameId: String, uid: String) async throws {
        let ref = gameRef(gameId)

        // Fetch current state
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard dict["undoRequest"] != nil else {
            throw GameError.noUndoPending
        }

        var updates: [String: Any] = [
            "undoRequest": NSNull(),
            "updatedAt": ServerValue.timestamp()
        ]

        // Re-stamp turnStartedAt if timer is enabled (rejection resets timer)
        if dict["timerDuration"] != nil {
            updates["turnStartedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        }

        try await ref.updateChildValues(updates)
    }

    // MARK: - Auto-pass turn

    func autoPassTurn(gameId: String, expectedTurn: Stone, expectedTurnStartedAt: Int) async throws {
        let ref = gameRef(gameId)

        // Fetch current state and verify conditions before updating
        let snapshot = try await ref.getData()
        guard let dict = snapshot.value as? [String: Any] else {
            throw GameError.gameNotFound
        }

        guard let statusRaw = dict["status"] as? String,
              statusRaw == GameStatus.playing.rawValue else {
            throw GameError.gameNotActive
        }

        guard let turnRaw = dict["turn"] as? String,
              let turn = Stone(rawValue: turnRaw),
              turn == expectedTurn else {
            throw GameError.turnAlreadyAdvanced
        }

        // Check turnStartedAt with 300ms tolerance
        if let turnStartedAt = dict["turnStartedAt"] as? Int {
            let delta = abs(turnStartedAt - expectedTurnStartedAt)
            guard delta <= 300 else {
                throw GameError.turnAlreadyAdvanced
            }
        }

        // Update: flip turn
        var updates: [String: Any] = [
            "turn": turn.opposite.rawValue,
            "updatedAt": Int(Date().timeIntervalSince1970 * 1000)
        ]

        // Re-stamp turnStartedAt if timer is enabled (critical fix for continuous turning)
        if dict["timerDuration"] != nil {
            updates["turnStartedAt"] = Int(Date().timeIntervalSince1970 * 1000)
        }

        try await ref.updateChildValues(updates)
    }

    // MARK: - Codec

    private static func decodeGameState(from snapshot: DataSnapshot) -> GameState? {
        guard snapshot.exists(), let dict = snapshot.value as? [String: Any] else {
            return nil
        }
        return decodeGameState(from: dict)
    }

    private static func decodeGameState(from dict: [String: Any]) -> GameState? {
        guard let statusRaw = dict["status"] as? String,
              let status = GameStatus(rawValue: statusRaw) else {
            return nil
        }
        guard let turnRaw = dict["turn"] as? String,
              let turn = Stone(rawValue: turnRaw) else {
            return nil
        }
        guard let round = dict["round"] as? Int else {
            return nil
        }
        guard let moveCount = dict["moveCount"] as? Int else {
            return nil
        }
        guard let createdBy = dict["createdBy"] as? String else {
            return nil
        }

        var board: [Cell: Stone] = [:]
        if let boardDict = dict["board"] as? [String: Any] {
            for (key, value) in boardDict {
                guard let cell = Cell(key: key),
                      let stoneRaw = value as? String,
                      let stone = Stone(rawValue: stoneRaw) else {
                    continue
                }
                board[cell] = stone
            }
        }

        var lastMove: LastMove?
        if let lastMoveDict = dict["lastMove"] as? [String: Any],
           let r = lastMoveDict["r"] as? Int,
           let c = lastMoveDict["c"] as? Int,
           let colorRaw = lastMoveDict["color"] as? String,
           let color = Stone(rawValue: colorRaw) {
            lastMove = LastMove(r: r, c: c, color: color)
        }

        let result = (dict["result"] as? String).flatMap(GameResult.init(rawValue:))

        var winningLine: [Cell]?
        if let lineArray = dict["winningLine"] as? [[String: Any]] {
            winningLine = lineArray.compactMap { entry in
                guard let r = entry["r"] as? Int, let c = entry["c"] as? Int else { return nil }
                return Cell(r: r, c: c)
            }
        }

        var players: [Stone: PlayerSeat] = [:]
        if let playersDict = dict["players"] as? [String: Any] {
            for (colorKey, seatValue) in playersDict {
                guard let color = Stone(rawValue: colorKey),
                      let seatDict = seatValue as? [String: Any],
                      let uid = seatDict["uid"] as? String else {
                    continue
                }
                let joinedAt = seatDict["joinedAt"] as? Int ?? 0
                let name = seatDict["name"] as? String
                let active = seatDict["active"] as? Bool
                players[color] = PlayerSeat(uid: uid, joinedAt: joinedAt, name: name, active: active)
            }
        }

        var rematchVotes: Set<String> = []
        if let rematchDict = dict["rematch"] as? [String: Any] {
            rematchVotes = Set(rematchDict.keys)
        }

        var speaking: [Stone: Bool] = [:]
        if let speakingDict = dict["speaking"] as? [String: Any] {
            for (colorKey, value) in speakingDict {
                guard let color = Stone(rawValue: colorKey),
                      let isSpeaking = value as? Bool else {
                    continue
                }
                speaking[color] = isSpeaking
            }
        }

        var undoRequest: UndoRequest?
        if let undoRequestDict = dict["undoRequest"] as? [String: Any],
           let requestedBy = undoRequestDict["requestedBy"] as? String,
           let createdAt = undoRequestDict["createdAt"] as? Int {
            undoRequest = UndoRequest(requestedBy: requestedBy, createdAt: createdAt)
        }

        var previousLastMove: LastMove?
        if let previousLastMoveDict = dict["previousLastMove"] as? [String: Any],
           let r = previousLastMoveDict["r"] as? Int,
           let c = previousLastMoveDict["c"] as? Int,
           let colorRaw = previousLastMoveDict["color"] as? String,
           let color = Stone(rawValue: colorRaw) {
            previousLastMove = LastMove(r: r, c: c, color: color)
        }

        let timerDuration = dict["timerDuration"] as? Int
        let turnStartedAt = dict["turnStartedAt"] as? Int

        var scores: [String: Int] = [:]
        if let scoresDict = dict["scores"] as? [String: Any] {
            for (uid, score) in scoresDict {
                if let scoreInt = score as? Int {
                    scores[uid] = scoreInt
                }
            }
        }

        return GameState(
            status: status,
            turn: turn,
            round: round,
            moveCount: moveCount,
            board: board,
            lastMove: lastMove,
            result: result,
            winningLine: winningLine,
            players: players,
            rematchVotes: rematchVotes,
            undoRequest: undoRequest,
            previousLastMove: previousLastMove,
            createdBy: createdBy,
            speaking: speaking,
            timerDuration: timerDuration,
            turnStartedAt: turnStartedAt,
            scores: scores
        )
    }
}

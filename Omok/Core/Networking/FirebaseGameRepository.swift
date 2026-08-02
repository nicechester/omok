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

    // MARK: - Create

    func createGame(gameId: String, creatorUid: String, creatorName: String) async throws {
        let sanitizedName = PlayerName.sanitize(creatorName)
        var blackSeat: [String: Any] = [
            "uid": creatorUid,
            "joinedAt": ServerValue.timestamp()
        ]
        if !sanitizedName.isEmpty {
            blackSeat["name"] = sanitizedName
        }
        let data: [String: Any] = [
            "status": GameStatus.waiting.rawValue,
            "turn": Stone.black.rawValue,
            "round": 0,
            "moveCount": 0,
            "players": [
                "black": blackSeat
            ],
            "createdBy": creatorUid,
            "createdAt": ServerValue.timestamp(),
            "updatedAt": ServerValue.timestamp()
        ]
        try await gameRef(gameId).setValue(data)
    }

    // MARK: - Claim seat

    func claimSeat(gameId: String, uid: String, name: String) async throws -> Stone {
        let ref = gameRef(gameId)
        var failure: GameError?
        let sanitizedName = PlayerName.sanitize(name)

        let (_, snapshot) = try await runTransaction(ref) { currentData in
            guard var dict = currentData.value as? [String: Any] else {
                failure = .gameNotFound
                return .abort()
            }

            var players = dict["players"] as? [String: Any] ?? [:]

            for color in [Stone.black, Stone.white] {
                guard var seat = players[color.rawValue] as? [String: Any],
                      seat["uid"] as? String == uid else {
                    continue
                }

                let existingName = seat["name"] as? String ?? ""
                if existingName != sanitizedName, !sanitizedName.isEmpty {
                    seat["name"] = sanitizedName
                    players[color.rawValue] = seat
                    dict["players"] = players
                    dict["updatedAt"] = Self.nowMillis()
                    currentData.value = dict
                    return .success(withValue: currentData)
                }

                return .success(withValue: currentData)
            }

            let blackTaken = players[Stone.black.rawValue] != nil
            let whiteTaken = players[Stone.white.rawValue] != nil

            guard !(blackTaken && whiteTaken) else {
                failure = .gameFull
                return .abort()
            }

            let seatColor: Stone = blackTaken ? .white : .black
            var newSeat: [String: Any] = [
                "uid": uid,
                "joinedAt": Self.nowMillis()
            ]
            if !sanitizedName.isEmpty {
                newSeat["name"] = sanitizedName
            }
            players[seatColor.rawValue] = newSeat
            dict["players"] = players

            if players[Stone.black.rawValue] != nil && players[Stone.white.rawValue] != nil {
                dict["status"] = GameStatus.playing.rawValue
            }
            dict["updatedAt"] = Self.nowMillis()

            currentData.value = dict
            return .success(withValue: currentData)
        }

        if let failure {
            throw failure
        }

        guard let dict = snapshot.value as? [String: Any],
              let players = dict["players"] as? [String: Any] else {
            throw GameError.gameNotFound
        }

        for (colorKey, seatValue) in players {
            guard let color = Stone(rawValue: colorKey),
                  let seatDict = seatValue as? [String: Any],
                  seatDict["uid"] as? String == uid else {
                continue
            }
            return color
        }

        throw GameError.gameFull
    }

    // MARK: - Place stone

    func placeStone(gameId: String, at cell: Cell, uid: String) async throws {
        guard GomokuRules.isValid(cell: cell) else {
            throw GameError.cellOccupied
        }

        let ref = gameRef(gameId)
        var failure: GameError?

        _ = try await runTransaction(ref) { currentData in
            guard var dict = currentData.value as? [String: Any] else {
                failure = .gameNotFound
                return .abort()
            }

            guard let statusRaw = dict["status"] as? String,
                  statusRaw == GameStatus.playing.rawValue else {
                failure = .gameNotActive
                return .abort()
            }

            guard let turnRaw = dict["turn"] as? String,
                  let turn = Stone(rawValue: turnRaw) else {
                failure = .gameNotActive
                return .abort()
            }

            guard let players = dict["players"] as? [String: Any],
                  let seatDict = players[turn.rawValue] as? [String: Any],
                  seatDict["uid"] as? String == uid else {
                failure = .notYourTurn
                return .abort()
            }

            var board = dict["board"] as? [String: Any] ?? [:]
            let key = cell.key
            guard board[key] == nil else {
                failure = .cellOccupied
                return .abort()
            }

            board[key] = turn.rawValue
            dict["board"] = board

            let moveCount = (dict["moveCount"] as? Int ?? 0) + 1
            dict["moveCount"] = moveCount
            dict["lastMove"] = ["r": cell.r, "c": cell.c, "color": turn.rawValue]
            dict["turn"] = turn.opposite.rawValue
            dict["updatedAt"] = Self.nowMillis()

            var boardCells: [Cell: Stone] = [:]
            for (boardKey, boardValue) in board {
                guard let boardCell = Cell(key: boardKey),
                      let stoneRaw = boardValue as? String,
                      let stone = Stone(rawValue: stoneRaw) else {
                    continue
                }
                boardCells[boardCell] = stone
            }

            if let line = GomokuRules.winningLine(board: boardCells, from: cell, color: turn) {
                dict["status"] = GameStatus.finished.rawValue
                dict["result"] = turn.rawValue
                dict["winningLine"] = line.map { ["r": $0.r, "c": $0.c] }
            } else if GomokuRules.isBoardFull(moveCount: moveCount) {
                dict["status"] = GameStatus.finished.rawValue
                dict["result"] = GameResult.draw.rawValue
            }

            currentData.value = dict
            return .success(withValue: currentData)
        }

        if let failure {
            throw failure
        }
    }

    // MARK: - Rematch

    func voteRematch(gameId: String, uid: String) async throws {
        try await gameRef(gameId).child("rematch").child(uid).setValue(true)
    }

    func resetForRematch(gameId: String) async throws {
        let ref = gameRef(gameId)
        var failure: GameError?

        _ = try await runTransaction(ref) { currentData in
            guard var dict = currentData.value as? [String: Any] else {
                failure = .gameNotFound
                return .abort()
            }

            // Idempotent guard: if the game isn't finished, either it was
            // already reset by the other client's racing transaction, or a
            // rematch was requested out of turn. Abort silently (no failure
            // set) so a harmless double-fire never surfaces an error.
            guard let statusRaw = dict["status"] as? String,
                  statusRaw == GameStatus.finished.rawValue else {
                return .abort()
            }

            let round = (dict["round"] as? Int ?? 0) + 1
            dict["round"] = round
            dict["moveCount"] = 0
            dict["board"] = NSNull()
            dict["lastMove"] = NSNull()
            dict["result"] = NSNull()
            dict["winningLine"] = NSNull()
            dict["rematch"] = NSNull()
            dict["turn"] = (round % 2 == 0 ? Stone.black : Stone.white).rawValue
            dict["status"] = GameStatus.playing.rawValue
            dict["updatedAt"] = Self.nowMillis()

            currentData.value = dict
            return .success(withValue: currentData)
        }

        if let failure {
            throw failure
        }
    }

    // MARK: - Transaction helper

    /// Wraps `runTransactionBlock` (there is no async transaction API in the
    /// SDK) in a checked continuation. The transaction block runs
    /// synchronously (possibly more than once, on retry) on Firebase's
    /// internal queue before the completion block fires, so callers may
    /// safely capture a local `var` to record why a `.abort()` happened.
    private func runTransaction(
        _ ref: DatabaseReference,
        _ block: @escaping (MutableData) -> TransactionResult
    ) async throws -> (committed: Bool, snapshot: DataSnapshot) {
        try await withCheckedThrowingContinuation { continuation in
            ref.runTransactionBlock(block) { error, committed, snapshot in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let snapshot else {
                    continuation.resume(throwing: GameError.gameNotFound)
                    return
                }
                continuation.resume(returning: (committed, snapshot))
            }
        }
    }

    private static func nowMillis() -> Int {
        Int(Date().timeIntervalSince1970 * 1000)
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
              let status = GameStatus(rawValue: statusRaw),
              let turnRaw = dict["turn"] as? String,
              let turn = Stone(rawValue: turnRaw),
              let round = dict["round"] as? Int,
              let moveCount = dict["moveCount"] as? Int,
              let createdBy = dict["createdBy"] as? String else {
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
                players[color] = PlayerSeat(uid: uid, joinedAt: joinedAt, name: name)
            }
        }

        var rematchVotes: Set<String> = []
        if let rematchDict = dict["rematch"] as? [String: Any] {
            rematchVotes = Set(rematchDict.keys)
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
            createdBy: createdBy
        )
    }
}

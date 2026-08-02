import Foundation

actor FakeGameRepository: GameRepository {
    private var games: [String: GameState] = [:]
    private var listeners: [String: [(GameState?) -> Void]] = [:]

    nonisolated func listenToGame(gameId: String) -> AsyncStream<GameState?> {
        return AsyncStream { continuation in
            Task {
                let state = await self.games[gameId]
                continuation.yield(state)
            }

            continuation.onTermination = { _ in
                // Cleanup: would unregister listener here in a real implementation
            }
        }
    }

    func createGame(gameId: String, creatorUid: String, creatorName: String) async throws {
        guard games[gameId] == nil else {
            throw GameError.gameNotFound
        }

        let sanitizedName = PlayerName.sanitize(creatorName)
        let state = GameState(
            status: .waiting,
            turn: .black,
            round: 0,
            moveCount: 0,
            board: [:],
            lastMove: nil,
            result: nil,
            winningLine: nil,
            players: [.black: PlayerSeat(
                uid: creatorUid,
                joinedAt: Int(Date().timeIntervalSince1970 * 1000),
                name: sanitizedName.isEmpty ? nil : sanitizedName
            )],
            rematchVotes: [],
            createdBy: creatorUid
        )

        games[gameId] = state
        await notifyListeners(gameId: gameId, state: state)
    }

    func claimSeat(gameId: String, uid: String, name: String) async throws -> Stone {
        guard let state = games[gameId] else {
            throw GameError.gameNotFound
        }

        let sanitizedName = PlayerName.sanitize(name)

        // If already has a seat, rebuild players with the sanitized name if
        // it differs (mirrors the Firebase reconnect/rename branch), then
        // return the seat.
        if let seat = state.seat(of: uid) {
            let existingSeat = state.players[seat]
            let existingName = existingSeat?.name ?? ""
            if existingName != sanitizedName, !sanitizedName.isEmpty {
                var updatedPlayers = state.players
                updatedPlayers[seat] = PlayerSeat(
                    uid: uid,
                    joinedAt: existingSeat?.joinedAt ?? 0,
                    name: sanitizedName
                )

                let updatedState = GameState(
                    status: state.status,
                    turn: state.turn,
                    round: state.round,
                    moveCount: state.moveCount,
                    board: state.board,
                    lastMove: state.lastMove,
                    result: state.result,
                    winningLine: state.winningLine,
                    players: updatedPlayers,
                    rematchVotes: state.rematchVotes,
                    createdBy: state.createdBy
                )

                games[gameId] = updatedState
                await notifyListeners(gameId: gameId, state: updatedState)
            }

            return seat
        }

        // If both seats taken by others, spectator
        if state.players.count >= 2 {
            throw GameError.gameFull
        }

        // Claim empty seat
        let emptyColor: Stone = state.players[.black] == nil ? .black : .white
        var updatedPlayers = state.players
        updatedPlayers[emptyColor] = PlayerSeat(
            uid: uid,
            joinedAt: Int(Date().timeIntervalSince1970 * 1000),
            name: sanitizedName.isEmpty ? nil : sanitizedName
        )

        let newStatus: GameStatus = updatedPlayers.count >= 2 ? .playing : state.status

        let updatedState = GameState(
            status: newStatus,
            turn: state.turn,
            round: state.round,
            moveCount: state.moveCount,
            board: state.board,
            lastMove: state.lastMove,
            result: state.result,
            winningLine: state.winningLine,
            players: updatedPlayers,
            rematchVotes: state.rematchVotes,
            createdBy: state.createdBy
        )

        games[gameId] = updatedState
        await notifyListeners(gameId: gameId, state: updatedState)
        return emptyColor
    }

    func placeStone(gameId: String, at cell: Cell, uid: String) async throws {
        guard let state = games[gameId] else {
            throw GameError.gameNotFound
        }

        guard state.status == .playing else {
            throw GameError.gameNotActive
        }

        guard let mySeat = state.seat(of: uid), mySeat == state.turn else {
            throw GameError.notYourTurn
        }

        guard state.board[cell] == nil else {
            throw GameError.cellOccupied
        }

        var updatedBoard = state.board
        updatedBoard[cell] = state.turn

        let lastMove = LastMove(r: cell.r, c: cell.c, color: state.turn)
        let updatedMoveCount = state.moveCount + 1
        let nextTurn = state.turn.opposite

        // Check for win
        let (finalStatus, finalResult, winningLine) = if let winningLine = GomokuRules.winningLine(board: updatedBoard, from: cell, color: lastMove.color) {
            (.finished as GameStatus, GameResult(rawValue: lastMove.color.rawValue), winningLine as [Cell]?)
        } else if GomokuRules.isBoardFull(moveCount: updatedMoveCount) {
            (.finished as GameStatus, GameResult.draw, nil as [Cell]?)
        } else {
            (state.status, state.result, nil as [Cell]?)
        }

        let updatedState = GameState(
            status: finalStatus,
            turn: nextTurn,
            round: state.round,
            moveCount: updatedMoveCount,
            board: updatedBoard,
            lastMove: lastMove,
            result: finalResult,
            winningLine: winningLine,
            players: state.players,
            rematchVotes: state.rematchVotes,
            createdBy: state.createdBy
        )

        games[gameId] = updatedState
        await notifyListeners(gameId: gameId, state: updatedState)
    }

    func voteRematch(gameId: String, uid: String) async throws {
        guard let state = games[gameId] else {
            throw GameError.gameNotFound
        }

        var votes = state.rematchVotes
        votes.insert(uid)

        let updatedState = GameState(
            status: state.status,
            turn: state.turn,
            round: state.round,
            moveCount: state.moveCount,
            board: state.board,
            lastMove: state.lastMove,
            result: state.result,
            winningLine: state.winningLine,
            players: state.players,
            rematchVotes: votes,
            createdBy: state.createdBy
        )

        games[gameId] = updatedState
        await notifyListeners(gameId: gameId, state: updatedState)
    }

    func resetForRematch(gameId: String) async throws {
        guard let state = games[gameId] else {
            throw GameError.gameNotFound
        }

        guard state.status == .finished else {
            throw GameError.gameNotActive
        }

        let nextRound = state.round + 1
        let nextTurn: Stone = (nextRound % 2 == 0) ? .black : .white

        let updatedState = GameState(
            status: .playing,
            turn: nextTurn,
            round: nextRound,
            moveCount: 0,
            board: [:],
            lastMove: nil,
            result: nil,
            winningLine: nil,
            players: state.players,
            rematchVotes: [],
            createdBy: state.createdBy
        )

        games[gameId] = updatedState
        await notifyListeners(gameId: gameId, state: updatedState)
    }

    private func notifyListeners(gameId: String, state: GameState) {
        if let callbacks = listeners[gameId] {
            for callback in callbacks {
                callback(state)
            }
        }
    }

    // MARK: - Preview State

    static func previewState() -> GameState {
        var board: [Cell: Stone] = [:]
        board[Cell(r: 7, c: 7)] = .black
        board[Cell(r: 7, c: 8)] = .white
        board[Cell(r: 8, c: 7)] = .black
        board[Cell(r: 8, c: 8)] = .white

        return GameState(
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
            createdBy: "user1"
        )
    }
}

import Foundation
import FirebaseDatabase

/// LocalGameRepository wraps a game repository and injects AI moves for single-player games.
/// The human always plays black (gets the first move); the AI plays white.
class LocalGameRepository: GameRepository {
    private let baseRepository: GameRepository
    private let aiPlayer: AIPlayer
    private let difficulty: AIDifficulty
    private let humanUid: String
    private static let aiUid = "ai-player"

    init(difficulty: AIDifficulty, localUid: String, baseRepository: GameRepository = FirebaseGameRepository()) {
        self.difficulty = difficulty
        self.humanUid = localUid
        self.baseRepository = baseRepository
        // AI always plays white; human always plays black
        self.aiPlayer = AIPlayer(difficulty: difficulty, aiColor: .white)
    }

    // MARK: - Delegated methods (pass through to base repository)

    func listenToGame(gameId: String) -> AsyncStream<GameState?> {
        baseRepository.listenToGame(gameId: gameId)
    }

    func fetchGame(gameId: String) async throws -> GameState? {
        try await baseRepository.fetchGame(gameId: gameId)
    }

    func createGame(gameId: String, creatorUid: String, creatorName: String, timerDuration: Int?) async throws {
        try await createAIGame(gameId: gameId, creatorUid: creatorUid, creatorName: creatorName, timerDuration: timerDuration)
    }

    private func createAIGame(gameId: String, creatorUid: String, creatorName: String, timerDuration: Int?) async throws {
        let db = Database.database().reference()
        let sanitizedName = PlayerName.sanitize(creatorName)
        
        var humanPlayer: [String: Any] = [
            "color": Stone.black.rawValue,
            "joinedAt": ServerValue.timestamp(),
            "active": true
        ]
        if !sanitizedName.isEmpty {
            humanPlayer["name"] = sanitizedName
        }
        
        let aiPlayerData: [String: Any] = [
            "color": Stone.white.rawValue,
            "joinedAt": ServerValue.timestamp(),
            "name": "AI (\(difficulty.displayName))",
            "active": true
        ]
        
        var data: [String: Any] = [
            "status": GameStatus.playing.rawValue,
            "turn": Stone.black.rawValue,
            "round": 0,
            "moveCount": 0,
            "players": [
                creatorUid: humanPlayer,
                Self.aiUid: aiPlayerData
            ],
            "scores": [:],
            "createdBy": creatorUid,
            "createdAt": ServerValue.timestamp(),
            "updatedAt": ServerValue.timestamp()
        ]
        if let duration = timerDuration {
            data["timerDuration"] = duration
            data["turnStartedAt"] = ServerValue.timestamp()
        }
        
        try await db.child("omok/games").child(gameId).setValue(data)
    }

    func claimSeat(gameId: String, uid: String, name: String) async throws -> Stone {
        try await baseRepository.claimSeat(gameId: gameId, uid: uid, name: name)
    }

    func forfeit(gameId: String, uid: String) async throws {
        try await baseRepository.forfeit(gameId: gameId, uid: uid)
    }

    func voteRematch(gameId: String, uid: String) async throws {
        try await baseRepository.voteRematch(gameId: gameId, uid: uid)
        // AI auto-votes for rematch
        try await baseRepository.voteRematch(gameId: gameId, uid: Self.aiUid)
    }

    func resetForRematch(gameId: String) async throws {
        try await baseRepository.resetForRematch(gameId: gameId)
    }

    func updateSpeaking(gameId: String, uid: String, isSpeaking: Bool) async throws {
        // No-op for AI games (no voice chat)
    }

    func updatePlayerActive(gameId: String, uid: String, isActive: Bool) async throws {
        try await baseRepository.updatePlayerActive(gameId: gameId, uid: uid, isActive: isActive)
    }

    func requestUndo(gameId: String, uid: String) async throws {
        throw GameError.undoNotAllowed
    }

    func approveUndo(gameId: String, uid: String) async throws {
        throw GameError.undoNotAllowed
    }

    func rejectUndo(gameId: String, uid: String) async throws {
        // No-op
    }

    func autoPassTurn(gameId: String, expectedTurn: Stone, expectedTurnStartedAt: Int) async throws {
        try await baseRepository.autoPassTurn(gameId: gameId, expectedTurn: expectedTurn, expectedTurnStartedAt: expectedTurnStartedAt)
    }

    func deleteGame(gameId: String, uid: String) async throws {
        try await baseRepository.deleteGame(gameId: gameId, uid: uid)
    }

    // MARK: - AI-specific methods

    /// Place a stone for the human player.
    /// After successful placement, the AI will automatically respond.
    func placeStone(gameId: String, at cell: Cell, uid: String) async throws {
        try await baseRepository.placeStone(gameId: gameId, at: cell, uid: uid)
    }

    /// Perform the AI's move: fetch current game state, compute best move, and place it.
    /// Called after the human's turn completes.
    func performAIMove(gameId: String) async throws {
        guard let game = try await baseRepository.fetchGame(gameId: gameId) else {
            throw GameError.gameNotFound
        }

        // Determine AI's current color from game state
        guard let aiColor = game.players[.black]?.uid == Self.aiUid ? Stone.black :
                            game.players[.white]?.uid == Self.aiUid ? Stone.white : nil else {
            return
        }

        guard game.status == .playing, game.turn == aiColor else { return }

        let currentAIPlayer = aiColor == aiPlayer.aiColor ? aiPlayer : AIPlayer(difficulty: difficulty, aiColor: aiColor)
        let bestMove = await currentAIPlayer.findBestMove(board: game.board, moveCount: game.moveCount)
        guard let move = bestMove else { return }

        do {
            try await baseRepository.placeStone(gameId: gameId, at: move, uid: Self.aiUid)
        } catch {
            // Silently ignore conflicts
        }
    }
}

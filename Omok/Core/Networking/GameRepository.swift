import Foundation

protocol GameRepository {
    func listenToGame(gameId: String) -> AsyncStream<GameState?>
    func fetchGame(gameId: String) async throws -> GameState?
    func createGame(gameId: String, creatorUid: String, creatorName: String, timerDuration: Int?) async throws
    func claimSeat(gameId: String, uid: String, name: String) async throws -> Stone
    func placeStone(gameId: String, at cell: Cell, uid: String) async throws
    func forfeit(gameId: String, uid: String) async throws
    func voteRematch(gameId: String, uid: String) async throws
    func resetForRematch(gameId: String) async throws
    func updateSpeaking(gameId: String, uid: String, isSpeaking: Bool) async throws
    func updatePlayerActive(gameId: String, uid: String, isActive: Bool) async throws
    func requestUndo(gameId: String, uid: String) async throws
    func approveUndo(gameId: String, uid: String) async throws
    func rejectUndo(gameId: String, uid: String) async throws
    func autoPassTurn(gameId: String, expectedTurn: Stone, expectedTurnStartedAt: Int) async throws
    func sendReaction(gameId: String, uid: String, emoji: String) async throws
    func deleteGame(gameId: String, uid: String) async throws
}

enum GameError: LocalizedError {
    case gameNotFound
    case gameFull
    case notYourTurn
    case cellOccupied
    case gameNotActive
    case undoNotAllowed
    case undoAlreadyPending
    case noUndoPending
    case turnAlreadyAdvanced
    case deleteNotAllowed
    case openThreesForbidden

    var errorDescription: String? {
        switch self {
        case .gameNotFound:
            return "No game found with that code."
        case .gameFull:
            return "This game already has two players."
        case .notYourTurn:
            return "It's not your turn."
        case .cellOccupied:
            return "That cell is already taken."
        case .gameNotActive:
            return "This game isn't active."
        case .undoNotAllowed:
            return "Cannot undo before the second move."
        case .undoAlreadyPending:
            return "An undo request is already pending."
        case .noUndoPending:
            return "No undo request to reject."
        case .turnAlreadyAdvanced:
            return "Turn already advanced."
        case .deleteNotAllowed:
            return "Can't delete a room while a game is in progress."
        case .openThreesForbidden:
            return "Cannot create two open threes in one move (3x3 rule)."
        }
    }
}

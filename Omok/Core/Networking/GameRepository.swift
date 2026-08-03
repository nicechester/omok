import Foundation

protocol GameRepository {
    func listenToGame(gameId: String) -> AsyncStream<GameState?>
    func createGame(gameId: String, creatorUid: String, creatorName: String) async throws
    func claimSeat(gameId: String, uid: String, name: String) async throws -> Stone
    func placeStone(gameId: String, at cell: Cell, uid: String) async throws
    func voteRematch(gameId: String, uid: String) async throws
    func resetForRematch(gameId: String) async throws
    func updateSpeaking(gameId: String, uid: String, isSpeaking: Bool) async throws
}

enum GameError: LocalizedError {
    case gameNotFound
    case gameFull
    case notYourTurn
    case cellOccupied
    case gameNotActive

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
        }
    }
}

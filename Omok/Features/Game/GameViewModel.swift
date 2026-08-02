import Foundation
import Observation

@Observable
@MainActor
final class GameViewModel {
    let gameId: String

    var game: GameState?
    var mySeat: Stone?
    var errorMessage: String?
    var gameNotFound = false

    private let uid: String
    private let playerName: String
    private let repository: GameRepository
    private let isCreator: Bool
    // A plain (non-actor-isolated) box so `deinit` — which runs nonisolated —
    // can cancel the listening task without touching a MainActor-isolated
    // stored property directly.
    private final class TaskBox {
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }
    private let listenTaskBox = TaskBox()
    private var listenTask: Task<Void, Never>? {
        get { listenTaskBox.task }
        set { listenTaskBox.task = newValue }
    }

    init(gameId: String, uid: String, playerName: String, repository: GameRepository = FirebaseGameRepository(), isCreator: Bool) {
        self.gameId = gameId
        self.uid = uid
        self.playerName = playerName
        self.repository = repository
        self.isCreator = isCreator
    }

    // MARK: - Derived state

    var isSpectator: Bool {
        mySeat == nil
    }

    var canPlay: Bool {
        guard let game, let mySeat, game.status == .playing else { return false }
        return game.turn == mySeat
    }

    var isMyWin: Bool {
        guard let game, game.status == .finished, let mySeat, let result = game.result else { return false }
        return Stone(rawValue: result.rawValue) == mySeat
    }

    var didVoteRematch: Bool {
        game?.rematchVotes.contains(uid) ?? false
    }

    var bothVotedRematch: Bool {
        (game?.rematchVotes.count ?? 0) >= 2
    }

    var opponentName: String? {
        guard let mySeat else { return nil }
        return game?.players[mySeat.opposite]?.displayName
    }

    var statusText: String {
        guard let game else { return "" }
        switch game.status {
        case .waiting:
            return "Waiting for opponent"
        case .playing:
            if isSpectator { return "Spectating" }
            if canPlay { return "Your turn" }
            return opponentName.map { "\($0)'s turn" } ?? "Opponent's turn"
        case .finished:
            return resultText(for: game)
        }
    }

    private func resultText(for game: GameState) -> String {
        guard let result = game.result else { return "" }
        switch result {
        case .draw:
            return "Draw"
        case .black, .white:
            if isSpectator {
                return "\(result.rawValue.capitalized) wins"
            }
            return isMyWin ? "You win" : "You lose"
        }
    }

    // MARK: - Lifecycle

    func start() async {
        if isCreator {
            do {
                try await repository.createGame(gameId: gameId, creatorUid: uid, creatorName: playerName)
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }

        do {
            mySeat = try await repository.claimSeat(gameId: gameId, uid: uid, name: playerName)
        } catch GameError.gameFull {
            mySeat = nil
        } catch GameError.gameNotFound {
            gameNotFound = true
            return
        } catch {
            errorMessage = error.localizedDescription
        }

        listenTask?.cancel()
        listenTask = Task { @MainActor [weak self, gameId, repository] in
            guard let self else { return }
            for await state in repository.listenToGame(gameId: gameId) {
                if Task.isCancelled { break }
                await self.handle(state)
            }
        }
    }

    private func handle(_ state: GameState?) async {
        game = state

        guard let state else {
            gameNotFound = true
            return
        }
        gameNotFound = false

        guard state.status == .finished, bothVotedRematch else { return }
        // Both clients may observe the second vote and both race to reset;
        // resetForRematch is idempotent (guards on status == finished), so
        // the double-fire is harmless.
        do {
            try await repository.resetForRematch(gameId: gameId)
        } catch {
            // Ignore: the other client's transaction likely already won.
        }
    }

    // MARK: - Actions

    func place(_ cell: Cell) async {
        guard canPlay else { return }
        do {
            try await repository.placeStone(gameId: gameId, at: cell, uid: uid)
        } catch let error as GameError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestRematch() async {
        do {
            try await repository.voteRematch(gameId: gameId, uid: uid)
        } catch let error as GameError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

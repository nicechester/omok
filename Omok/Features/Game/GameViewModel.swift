import Foundation
import Observation
import AudioToolbox
import UIKit

@Observable
@MainActor
final class GameViewModel {
    let gameId: String

    var game: GameState?
    var mySeat: Stone?
    var errorMessage: String?
    private var hadOpponent = false

    private let uid: String
    private let playerName: String
    private let repository: GameRepository
    private var backgroundedAt: Date?
    private var lastNotificationTime: Date?
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
    
    // A plain (non-actor-isolated) box for background task identifier
    private final class BackgroundTaskBox {
        var identifier: UIBackgroundTaskIdentifier = .invalid
    }
    private let backgroundTaskBox = BackgroundTaskBox()
    private var backgroundTask: UIBackgroundTaskIdentifier {
        get { backgroundTaskBox.identifier }
        set { backgroundTaskBox.identifier = newValue }
    }

    init(gameId: String, uid: String, playerName: String, repository: GameRepository = FirebaseGameRepository()) {
        self.gameId = gameId
        self.uid = uid
        self.playerName = playerName
        self.repository = repository
    }

    deinit {
        endBackgroundTask()
    }

    // MARK: - Background lifecycle

    func appDidEnterBackground() {
        backgroundedAt = Date()
        beginBackgroundTask()
    }

    func appDidBecomeActive() {
        backgroundedAt = nil
        endBackgroundTask()
    }

    private func beginBackgroundTask() {
        backgroundTask = UIApplication.shared.beginBackgroundTask { [weak self] in
            self?.endBackgroundTask()
        }
    }

    nonisolated private func endBackgroundTask() {
        if backgroundTaskBox.identifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskBox.identifier)
            backgroundTaskBox.identifier = .invalid
        }
    }

    private func notifyIfNeeded(_ state: GameState?, previous: GameState?) {
        guard !isSpectator, let backgroundedAt else { return }

        let now = Date()
        if let lastNotificationTime, now.timeIntervalSince(lastNotificationTime) < 5 {
            return
        }

        Task {
            let notificationManager = NotificationManager.shared

            // Notify on new opponent move
            if let lastMove = state?.lastMove, lastMove.color != mySeat {
                if previous?.lastMove?.r != lastMove.r || previous?.lastMove?.c != lastMove.c {
                    let name = opponentName ?? "Opponent"
                    await notificationManager.scheduleGameNotification(
                        gameId: gameId,
                        title: "Room \(gameId.uppercased())",
                        body: "\(name) made a move"
                    )
                    lastNotificationTime = now
                    return
                }
            }

            // Notify on game finish
            if state?.status == .finished, previous?.status != .finished {
                if let result = state?.result {
                    let body: String
                    let name = opponentName ?? "Opponent"
                    switch result {
                    case .draw:
                        body = "Game is a draw"
                    case .black, .white:
                        if let mySeat, Stone(rawValue: result.rawValue) == mySeat {
                            body = "You won"
                        } else {
                            body = "\(name) won the game"
                        }
                    }
                    await notificationManager.scheduleGameNotification(
                        gameId: gameId,
                        title: "Room \(gameId.uppercased())",
                        body: body
                    )
                    lastNotificationTime = now
                }
            }
        }
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
        do {
            mySeat = try await repository.claimSeat(gameId: gameId, uid: uid, name: playerName)
        } catch GameError.gameNotFound {
            // Game doesn't exist yet, create it (creator gets black seat)
            do {
                try await repository.createGame(gameId: gameId, creatorUid: uid, creatorName: playerName)
                mySeat = .black
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        } catch GameError.gameFull {
            mySeat = nil
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
        let previousGame = game
        guard let state else { return }
        game = state

        // Play sound when opponent joins
        if let mySeat,
           previousGame?.players[mySeat.opposite] == nil,
           state.players[mySeat.opposite] != nil {
            AudioServicesPlaySystemSound(1054) // subtle "tock" sound
        }

        // Notify if in background
        notifyIfNeeded(state, previous: previousGame)

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
    
    func forfeit() async {
        do {
            try await repository.forfeit(gameId: gameId, uid: uid)
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

    func updateSpeaking(_ isSpeaking: Bool) async {
        do {
            try await repository.updateSpeaking(gameId: gameId, uid: uid, isSpeaking: isSpeaking)
        } catch {
            print("Failed to update speaking state: \(error)")
        }
    }
}

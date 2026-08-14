import Foundation
import Observation
import AudioToolbox
import UIKit
import SwiftUI

@Observable
@MainActor
final class GameViewModel {
    let gameId: String

    var game: GameState?
    var mySeat: Stone?
    var errorMessage: String?
    var remainingSeconds: Int?
    var isAIThinking: Bool = false
    var isViewVisible: Bool = false
    private var hadOpponent = false
    private var currentScenePhase: ScenePhase = .active
    let timerDuration: Int?
    let aiDifficulty: AIDifficulty?

    private let uid: String
    private let playerName: String
    private let repository: GameRepository
    private var backgroundedAt: Date?
    private var lastNotificationTime: Date?
    // A plain box for AI move task
    private final class AIMoveTaskBox {
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }
    private let aiMoveTaskBox = AIMoveTaskBox()
    private var aiMoveTask: Task<Void, Never>? {
        get { aiMoveTaskBox.task }
        set { aiMoveTaskBox.task = newValue }
    }

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

    // A plain box for undo timeout task
    private final class UndoTimeoutTaskBox {
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }
    private let undoTimeoutTaskBox = UndoTimeoutTaskBox()
    private var undoTimeoutTask: Task<Void, Never>? {
        get { undoTimeoutTaskBox.task }
        set { undoTimeoutTaskBox.task = newValue }
    }

    // A plain box for timer task
    private final class TimerTaskBox {
        var task: Task<Void, Never>?
        deinit { task?.cancel() }
    }
    private let timerTaskBox = TimerTaskBox()
    private var timerTask: Task<Void, Never>? {
        get { timerTaskBox.task }
        set { timerTaskBox.task = newValue }
    }

    private var timerAnchor: (turn: Stone, turnStartedAt: Int)?

    init(gameId: String, uid: String, playerName: String, timerDuration: Int? = nil, aiDifficulty: AIDifficulty? = nil, repository: GameRepository = FirebaseGameRepository()) {
        self.gameId = gameId
        self.uid = uid
        self.playerName = playerName
        self.timerDuration = timerDuration
        self.aiDifficulty = aiDifficulty
        self.repository = repository
    }

    deinit {
        endBackgroundTask()
    }

    // MARK: - Background lifecycle

    func setScenePhase(_ phase: ScenePhase) {
        currentScenePhase = phase
    }

    func pauseTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    func markPlayerAsActive() {
        Task {
            try? await repository.updatePlayerActive(gameId: gameId, uid: uid, isActive: true)
        }
    }

    func markPlayerAsDisconnected() {
        Task {
            try? await repository.updatePlayerActive(gameId: gameId, uid: uid, isActive: false)
        }
    }

    func appDidEnterBackground() {
        backgroundedAt = Date()
        beginBackgroundTask()
        timerTask?.cancel()
        timerTask = nil
    }

    func appDidBecomeActive() {
        backgroundedAt = nil
        endBackgroundTask()
        UIApplication.shared.applicationIconBadgeNumber = 0
        if let game {
            updateTimerState(for: game, force: true)
        }

        // Update player's active status when coming back online
        if mySeat != nil {
            Task {
                try? await repository.updatePlayerActive(gameId: gameId, uid: uid, isActive: true)
            }
        }

        // Force listener to re-subscribe for fresh snapshot (fixes stale state like turn)
        if game != nil {
            listenTask?.cancel()
            listenTask = Task { @MainActor [weak self, gameId, repository] in
                guard let self else { return }
                for await state in repository.listenToGame(gameId: gameId) {
                    if Task.isCancelled { break }
                    await self.handle(state)
                }
            }
        }
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
        guard !isSpectator, let state else { return }
        guard !(isViewVisible && currentScenePhase == .active) else { return }

        let now = Date()
        if let lastNotificationTime, now.timeIntervalSince(lastNotificationTime) < 5 {
            return
        }

        Task {
            let notificationManager = NotificationManager.shared

            // Check if opponent is still in the game
            let opponentSeat = mySeat?.opposite
            let opponentStillSeated = opponentSeat.map { state.players[$0] != nil } ?? false

            // Notify on new opponent move (only if opponent still seated)
            if opponentStillSeated, let lastMove = state.lastMove, lastMove.color != mySeat {
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
            if state.status == .finished, previous?.status != .finished {
                if let result = state.result {
                    let body: String
                    switch result {
                    case .draw:
                        body = "Game is a draw"
                    case .black, .white:
                        if let mySeat, Stone(rawValue: result.rawValue) == mySeat {
                            body = "You won"
                        } else if opponentStillSeated {
                            let name = opponentName ?? "Opponent"
                            body = "\(name) won the game"
                        } else {
                            body = "Opponent abandoned"
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

    var isAIGame: Bool {
        aiDifficulty != nil
    }

    var isSpectator: Bool {
        mySeat == nil
    }

    var canPlay: Bool {
        guard let game, let mySeat, game.status == .playing else { return false }
        return game.turn == mySeat && game.undoRequest == nil && !isAIThinking
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
            if isAIThinking { return "AI thinking…" }
            if canPlay { return "Your turn" }
            return isAIGame ? "AI's turn" : (opponentName.map { "\($0)'s turn" } ?? "Opponent's turn")
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

    var canRequestUndo: Bool {
        guard let game, let mySeat, game.status == .playing else { return false }
        return game.moveCount >= 2 && game.undoRequest == nil && game.turn != mySeat
    }

    var undoRequestPending: Bool {
        game?.undoRequest != nil
    }

    var showUndoPrompt: Bool {
        guard let game, let mySeat, let undoRequest = game.undoRequest else { return false }
        // Show prompt to the opponent (not the requester)
        return undoRequest.requestedBy != uid
    }

    var undoRequesterName: String? {
        guard let game, let undoRequest = game.undoRequest else { return nil }
        guard let requesterSeat = game.seat(of: undoRequest.requestedBy) else { return nil }
        return game.players[requesterSeat]?.displayName
    }

    // MARK: - Lifecycle

    func start() async {
        do {
            mySeat = try await repository.claimSeat(gameId: gameId, uid: uid, name: playerName)
        } catch GameError.gameNotFound {
            // Game doesn't exist yet, create it (creator gets black seat)
            do {
                print("[GameViewModel] Creating new game: \(gameId)")
                try await repository.createGame(gameId: gameId, creatorUid: uid, creatorName: playerName, timerDuration: timerDuration)
                print("[GameViewModel] Game created successfully, claiming black seat")
                mySeat = .black
            } catch {
                let errorMsg = "Failed to create game: \(error.localizedDescription)"
                print("[GameViewModel] \(errorMsg)")
                errorMessage = errorMsg
                return
            }
        } catch GameError.gameFull {
            mySeat = nil
        } catch {
            let errorMsg = "Game error: \(error.localizedDescription)"
            print("[GameViewModel] \(errorMsg)")
            errorMessage = errorMsg
        }

        listenTask?.cancel()
        listenTask = Task { @MainActor [weak self, gameId, repository] in
            guard let self else { return }
            print("[GameViewModel] Starting to listen to game: \(gameId)")
            for await state in repository.listenToGame(gameId: gameId) {
                if Task.isCancelled { break }
                await self.handle(state)
            }
        }
    }

    private func handle(_ state: GameState?) async {
        let previousGame = game
        if state == nil && previousGame != nil {
            // Game was deleted by opponent
            errorMessage = "This game was deleted"
            game = nil
            return
        }
        guard let state else { return }
        game = state

        // Update mySeat from game state (handles color swap on rematch)
        mySeat = state.seat(of: uid)

        // Play sound when opponent joins
        if let mySeat,
           previousGame?.players[mySeat.opposite] == nil,
           state.players[mySeat.opposite] != nil {
            AudioServicesPlaySystemSound(1054) // subtle "tock" sound
        }

        // Notify if in background
        notifyIfNeeded(state, previous: previousGame)

        // Handle undo request state changes
        if state.undoRequest != nil, previousGame?.undoRequest == nil {
            // New undo request appeared; schedule timeout if we're the opponent
            if let undoRequest = state.undoRequest, undoRequest.requestedBy != uid {
                scheduleUndoAutoReject()
            }
        } else if state.undoRequest == nil, previousGame?.undoRequest != nil {
            // Undo request was resolved; cancel timeout
            undoTimeoutTask?.cancel()
            undoTimeoutTask = nil
        }

        // Update timer state
        updateTimerState(for: state, force: false)

        // If AI game and it's AI's turn at game start (e.g. after rematch color swap), trigger AI move
        if isAIGame, state.status == .playing, previousGame?.status != .playing,
           let mySeat, state.turn != mySeat {
            aiMoveTask = Task { @MainActor [weak self] in
                guard let self else { return }
                await self.performAIMove()
            }
        }

        guard state.status == .finished, bothVotedRematch else { return }
        // Only creator drives the reset to avoid race condition between clients
        guard state.createdBy == uid else { return }
        do {
            try await repository.resetForRematch(gameId: gameId)
        } catch {
            // Ignore if already reset
        }
    }

    // MARK: - Actions

    func place(_ cell: Cell) async {
        guard canPlay else { return }
        do {
            try await repository.placeStone(gameId: gameId, at: cell, uid: uid)
            // For AI games, start AI move in background after human move
            if isAIGame {
                aiMoveTask = Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.performAIMove()
                }
            }
        } catch let error as GameError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func forfeit() async {
        aiMoveTask?.cancel()
        aiMoveTask = nil
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

    private func performAIMove() async {
        guard let game, game.status == .playing else { return }
        guard let mySeat, game.turn != mySeat else { return }

        isAIThinking = true
        defer { isAIThinking = false }

        if let localRepo = repository as? LocalGameRepository {
            do {
                try await localRepo.performAIMove(gameId: gameId)
            } catch let error as GameError {
                errorMessage = error.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    func updateSpeaking(_ isSpeaking: Bool) async {
        do {
            try await repository.updateSpeaking(gameId: gameId, uid: uid, isSpeaking: isSpeaking)
        } catch {
            print("Failed to update speaking state: \(error)")
        }
    }

    func requestUndo() async {
        if isAIGame {
            errorMessage = "Undo is not available in AI games"
            return
        }
        do {
            try await repository.requestUndo(gameId: gameId, uid: uid)
        } catch let error as GameError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func approveUndo() async {
        if isAIGame {
            errorMessage = "Undo is not available in AI games"
            return
        }
        do {
            try await repository.approveUndo(gameId: gameId, uid: uid)
        } catch let error as GameError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rejectUndo() async {
        if isAIGame {
            return
        }
        do {
            try await repository.rejectUndo(gameId: gameId, uid: uid)
        } catch let error as GameError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleUndoAutoReject() {
        undoTimeoutTask?.cancel()
        undoTimeoutTask = Task { @MainActor [weak self, gameId, repository] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 seconds
            if Task.isCancelled { return }
            do {
                try await repository.rejectUndo(gameId: gameId, uid: uid)
            } catch {
                // Silently ignore: timeout reject is best-effort
            }
        }
    }

    private func updateTimerState(for state: GameState, force: Bool) {
        // Pause timer when app is backgrounded
        guard currentScenePhase == .active else {
            timerTask?.cancel()
            timerTask = nil
            return
        }

        // Stop ticking if undo request is pending
        if state.undoRequest != nil {
            timerTask?.cancel()
            timerTask = nil
            return
        }

        // Only process if status is playing
        guard state.status == .playing else {
            timerTask?.cancel()
            timerTask = nil
            remainingSeconds = nil
            return
        }

        // Check if timer is enabled
        guard let duration = state.timerDuration, let turnStartedAt = state.turnStartedAt else {
            timerTask?.cancel()
            timerTask = nil
            remainingSeconds = nil
            return
        }

        // If turn or turnStartedAt changed, or force recompute, restart ticking
        let needsRestart = force || timerAnchor?.turn != state.turn || timerAnchor?.turnStartedAt != turnStartedAt
        if needsRestart {
            timerTask?.cancel()
            timerAnchor = (turn: state.turn, turnStartedAt: turnStartedAt)
            startTicking(turn: state.turn, turnStartedAt: turnStartedAt, duration: duration)
        }
    }

    private func startTicking(turn: Stone, turnStartedAt: Int, duration: Int) {
        timerTask = Task { @MainActor [weak self, gameId, repository] in
            guard let self else { return }

            while !Task.isCancelled {
                // Stop ticking if app backgrounded or view disappeared
                guard self.currentScenePhase == .active else { return }

                let now = Int(Date().timeIntervalSince1970 * 1000)
                let elapsed = now - turnStartedAt
                let remaining = max(0, duration * 1000 - elapsed)
                let remainingInt = (remaining + 999) / 1000  // Round up to nearest second

                self.remainingSeconds = remainingInt

                if remainingInt <= 0 {
                    // Timer expired, try auto-pass
                    do {
                        try await repository.autoPassTurn(gameId: gameId, expectedTurn: turn, expectedTurnStartedAt: turnStartedAt)
                    } catch {
                        // Silently swallow turnAlreadyAdvanced and other errors
                    }
                    return
                }

                // Sleep for 1 second
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }
}

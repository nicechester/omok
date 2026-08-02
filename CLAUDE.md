# Omok (오목) — Project Guidelines for Claude Sessions

## Overview

Omok is a real-time two-player five-in-a-row game (gomoku). Architecture mirrors `shareddrawing` exactly: `@main` app that calls `FirebaseApp.configure()` and signs in anonymously before showing UI, an `@Observable` `AuthService`, a repository protocol + Firebase implementation exposing realtime data as an `AsyncStream`, an `@Observable` ViewModel, and a `Core/` + `Features/` + `Shared/` folder layout.

**Critical difference**: Drawing is append-only and conflict-free. Omok has three contended invariants:
- One stone per intersection
- One player per color
- Alternating turns

Every mutating repository call is an **RTDB transaction on the game node**, not a plain `setValue()`.

## Tech Stack

| Layer | Choice | Why |
|-------|--------|-----|
| UI | SwiftUI (iOS 17+) | Modern default; `Canvas` fast enough for board display |
| Input | SwiftUI `Canvas` + tap gesture | Stones sit on intersections, not inside cells |
| Firebase | SPM only (firebase-ios-sdk ≥ 12.16.0) | Official SDK; `FirebaseAuth` + `FirebaseDatabase` products only |
| Auth | Anonymous auth | Frictionless; no sign-up friction |
| Database | RTDB (game state) | Real-time, cheap, ordered, low-latency |
| Concurrency | async/await + AsyncStream | Modern Swift; clean abstraction over Firebase listeners |
| Architecture | MVVM + Repository pattern | Testable; `FakeGameRepository` for unit tests without network |

## Data Model: RTDB `omok/games/{gameId}` Schema

`gameId` = 5 characters from `0123456789abcdefghijklmnopqrstuvwxyz` (lowercase only; room codes are typed and read aloud, so avoid case ambiguity).

**Full schema:**

```
omok/games/{gameId}:
  status:      "waiting" | "playing" | "finished"
  turn:        "black" | "white"
  round:       0                              # increments per rematch
  moveCount:   0                              # 0...225
  board:                                      # absent when empty
    "7_7":     "black"
    "7_8":     "white"
  lastMove:    { r: 7, c: 8, color: "white" } # absent before first move
  result:      "black" | "white" | "draw"     # absent unless status == finished
  winningLine: [ {r:7,c:7}, ... x5 ]          # absent unless someone won
  players:
    black:     { uid: "<authUid>", joinedAt: 1730000000000, name: "Chester" }
    white:     { uid: "<authUid>", joinedAt: 1730000000000, name: "Chester" }
  rematch:     { "<uid>": true, "<uid>": true }  # cleared on reset
  createdBy:   "<authUid>"
  createdAt:   <ServerValue.timestamp()>
  updatedAt:   <ms since epoch, plain number>
```

### Player Nicknames

The `name` field in `players/{color}` is optional: games created before this feature lack it. Maximum 20 characters. Only the seat owner (the uid holding that color) can set or modify their own `name`; the opponent's `name` is read-only to each player. Players set a nickname on first run and can change it via the gear icon in the lobby; the opponent sees it in the status bar.

### Board Key Format Warning

Cell keys are **`"{row}_{col}"`** (e.g. `"7_7"`), *not* a flat integer index.

**Why underscore matters:** RTDB coerces a node whose keys are all numeric into a JSON array on read, which would silently turn `board` into a sparse `NSArray` and break `[String: Any]` decoding. The underscore keeps keys non-numeric and preserves the dictionary structure.

## Game Rules & Transactions

All game mutations go through RTDB transactions on the game node:

- **Create**: Write node with `status: "waiting"`, `turn: "black"`, `round: 0`, `moveCount: 0`, creator in `players/black`
- **Join/Claim seat**: Transaction that fills empty seat; if both filled, set `status: "playing"`. Reconnect returns your existing seat unchanged.
- **Place stone**: Transaction that guards `status == "playing"`, `players[turn].uid == uid`, and cell empty; then writes cell, increments `moveCount`, updates `lastMove`, flips `turn`. Runs `GomokuRules.winningLine()` inside the transaction; on win, set `status: "finished"`, `result`, `winningLine`. On 225 stones with no win, set `status: "finished"`, `result: "draw"`.
- **Rematch**: Each player writes `rematch/{uid}: true`. When both votes observed, a transaction resets: clears `board`, `result`, `winningLine`, `rematch`, increments `round`, sets `status: "playing"`, resets `turn` based on round parity for fairness. Seats stay fixed.

**Transaction execution is retry-safe**: bodies run multiple times on conflict, may first run against `nil` cache. Never create the node inside a transaction — abort instead. Use `Int(Date().timeIntervalSince1970 * 1000)` for `updatedAt` inside transactions (never read `ServerValue.timestamp()` inside transaction logic). Every `.validate` in security rules includes `|| data.val() === newData.val()` escape hatch because whole-node puts re-validate unchanged children.

## Project Structure (Mirrors shareddrawing)

```
Omok/                                   # Xcode project directory
  Omok.xcodeproj
  GoogleService-Info.plist              # ⚠️ NEVER commit
  README.md
  CLAUDE.md
  .gitignore
  RTDB_SECURITY_RULES.json
  OmokApp.swift                         # @main, FirebaseApp.configure()
  AuthService.swift                     # @Observable, anonymous auth only
  Core/
    Models/
      Stone.swift
      Cell.swift
      GameState.swift
    Networking/
      GameRepository.swift              # protocol
      FirebaseGameRepository.swift       # impl with transactions
      FakeGameRepository.swift           # test doubles
  Features/
    Lobby/
      GameIDView.swift                  # room-code join/create
    Game/
      GameView.swift                    # main game UI
      GameViewModel.swift               # @Observable, derives UI state
      BoardView.swift                   # Canvas + tap gesture
      GameStatusBar.swift               # room code, turn indicator
      ResultBanner.swift                # win/draw/rematch
  Shared/
    GomokuRules.swift                   # pure game logic, 4-direction line detection
```

## Key Implementation Notes

1. **`@Observable` and `@State`**: ViewModel is `@Observable`, held as `@State` in the view that constructs it (not passed in).

2. **AsyncStream listener lifetime**: Repository's `listenToGame()` returns an `AsyncStream<GameState?>`. ViewModel consumes it in a `Task` that's cancelled in `deinit` or when navigating back; this teardown calls `continuation.onTermination` to remove Firebase observers.

3. **FakeGameRepository**: In-memory implementation for previews and unit tests. Must implement the full `GameRepository` protocol with realistic response delays for believable testing.

4. **Numeric board keys → array coercion**: The `"7_7"` key format prevents RTDB from treating the board as a sparse array. If keys become numeric, decoding will silently fail.

5. **Whole-node snapshots**: Unlike shareddrawing's three child-event observers, Omok uses one `.value` observer on the entire game node. This ensures `board`, `turn`, and `status` are mutually consistent by construction (no window where board advanced but `turn` hadn't).

6. **Rematch idempotence**: Both clients may observe both votes and both fire `resetForRematch`. The reset transaction must be idempotent — guard on `status == "finished"` to ensure only one reset succeeds; retries against `status == "playing"` abort safely.

7. **Draw at exactly 225**: Check *after* the win check, so a winning 225th stone is a win, not a draw.

8. **Third participants**: No seat available → spectator mode. Full read, taps inert, status bar says "Spectating".

9. **Simultaneous taps on the same cell**: The losing transaction fails its guard; surface a transient message, never crash or leave a phantom stone.

10. **RTDB disk persistence**: Stays off (SDK default), matching shareddrawing. Enabling it would serve stale boards from cache on launch.

## Firebase Console Prerequisites

Before running: create a dedicated `omok` Firebase project (new, not shared with shareddrawing), enable Anonymous Auth, create a Realtime Database instance, and deploy `RTDB_SECURITY_RULES.json`. Download `GoogleService-Info.plist` to the repo root. See README.md for the 5 manual console steps.

## Important: GoogleService-Info.plist

**NEVER commit `GoogleService-Info.plist` to git.** It contains API keys tied to your Firebase project. The `.gitignore` blocks it. In CI/CD, inject it at build time from a secure secret.

## Testing Strategy

- **Unit tests**: `GomokuRules` (horizontal/vertical/diagonal win detection, edge cases, draw at 225, overline wins)
- **ViewModel tests**: `FakeGameRepository` (no network, deterministic, instant)
- **Integration tests**: Firebase Emulator Suite (`firebase emulators:start`) for realistic RTDB behavior
- **Manual end-to-end**: Two simulators creating and joining the same game, alternating moves, verifying win/rematch

## References

- Firebase iOS SDK: https://github.com/firebase/firebase-ios-sdk
- SwiftUI Canvas: https://developer.apple.com/documentation/swiftui/canvas
- Firebase Realtime Database Rules: https://firebase.google.com/docs/database/security
- shareddrawing CLAUDE.md for architecture patterns (MVVM, Repository, AsyncStream, @Observable)

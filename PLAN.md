# Omok (오목) — iOS Realtime 2-Player Gomoku: Implementation Plan

## Summary

A minimal SwiftUI + Firebase RTDB two-player five-in-a-row game living at `/Users/chester.kim/workspace/trashcan/omok`. It mirrors `shareddrawing`'s architecture verbatim: `@main` app that calls `FirebaseApp.configure()` and signs in anonymously before showing UI, an `@Observable` `AuthService`, a repository protocol + Firebase implementation exposing realtime data as an `AsyncStream`, an `@Observable` ViewModel, and a `Core/` + `Features/` + `Shared/` folder layout. Players meet via a 5-character room code, exactly like `CanvasIDView`'s canvas-ID join.

**What differs from shareddrawing, and why it matters:** drawing is append-only and conflict-free — every write is safe. Omok has three contended invariants (one stone per intersection, one player per color, alternating turns). Those need compare-and-set, so every mutating repository call is an **RTDB transaction on the game node**, not a plain `setValue`.

---

## Reference-project facts this plan is built on

Verified in the reference repo:

| Aspect | shareddrawing reality |
|---|---|
| Xcode project | `objectVersion = 70`, single app target, no test target |
| Source folders | `Core/`, `Features/`, `Shared/` are `PBXFileSystemSynchronizedRootGroup`s — files dropped in are auto-compiled, **no pbxproj edit needed** |
| Deployment | iOS 17.0, Swift 5.9, portrait only, generated Info.plist (`INFOPLIST_KEY_*`), team `K92B539W6W` |
| SPM | `firebase-ios-sdk` upToNextMajor from `12.16.0` (products `FirebaseAuth`, `FirebaseDatabase`), plus `GoogleSignIn-iOS` 7.0.0 and `vapor/jwt-kit` 5.6.0 (only for Google sign-in + GCS uploads — **Omok needs neither**) |
| Firebase project | `PROJECT_ID = shared-drawing`, RTDB `https://shared-drawing-default-rtdb.firebaseio.com`, `BUNDLE_ID = io.github.nicechester.shareddrawing` |
| Auth | `AuthService.signInAnonymously()` awaited behind a `ProgressView("Initializing...")` gate in `SharedDrawingApp.swift`; Google sign-in is optional account linking |
| Data path | `v2/canvases/{canvasId}/...`; deployed rules at shareddrawing's `RTDB_SECURITY_RULES.json` are wide open (`.read: true, .write: true`) — much looser than the CLAUDE.md doc claims |
| Realtime pattern | `listenToStrokes(canvasId:) -> AsyncStream<StrokeEvent>` wrapping `.childAdded/.childChanged/.childRemoved`, consumed by `for await event in ...` in the ViewModel, torn down via `continuation.onTermination` |
| Join UI | `CanvasIDView`: TextField + Create (random 5-char ID) / Join buttons → `navigationDestination` |

---

## 1. Project setup

### Xcode project
Create `Omok.xcodeproj` (app target `Omok`), matching shareddrawing's settings:

- `objectVersion = 70`, iOS 17.0, `SWIFT_VERSION = 5.9`, SwiftUI lifecycle
- `PRODUCT_BUNDLE_IDENTIFIER = io.github.nicechester.omok`
- `INFOPLIST_KEY_CFBundleDisplayName = Omok`, `LSApplicationCategoryType = public.app-category.games`, portrait-only
- `DEVELOPMENT_TEAM = K92B539W6W`, `CODE_SIGN_STYLE = Automatic`, `CODE_SIGNING_REQUIRED = NO` (simulator-friendly, as in the reference)
- **Declare `Core`, `Features`, `Shared` as `PBXFileSystemSynchronizedRootGroup`s.** This is the single most valuable thing to copy: later steps then add `.swift` files with zero project-file surgery.
- No `.entitlements` file (drop associated-domains; no Universal Links in MVP)

### SPM dependencies
Only `https://github.com/firebase/firebase-ios-sdk`, `upToNextMajorVersion` from `12.16.0`, linking **`FirebaseAuth` + `FirebaseDatabase`**. Omit `GoogleSignIn` and `jwt-kit` — anonymous auth needs neither, and dropping them cuts build time and removes the URL-scheme/Info.plist plumbing.

### Firebase config — DECIDED: brand-new `omok` Firebase project

**Decision (2026-07-31): create a fresh Firebase project for Omok** — fully isolated rules, quota, and analytics; zero risk of breaking shareddrawing. `GoogleService-Info.plist` is bound to a bundle ID anyway, so shareddrawing's file could not have been reused as-is.

Console prerequisites (human steps, document in README):
1. Create Firebase project (e.g. `omok`) at console.firebase.google.com
2. Add an iOS app with bundle ID `io.github.nicechester.omok`, download `GoogleService-Info.plist` into the repo root
3. Enable **Anonymous** sign-in under Authentication → Sign-in method
4. Create a **Realtime Database** instance (the `DATABASE_URL` lands in the plist; `Database.database().reference()` needs no code change)
5. Deploy `RTDB_SECURITY_RULES.json` (this project's rules only — no merging with shareddrawing's ruleset needed)

`.gitignore`: `GoogleService-Info.plist`, `build/`, `*.xcuserdatad`, `DerivedData/`. (Note: shareddrawing's CLAUDE.md says don't commit the plist, but the repo actually committed it. Follow the documented rule, not the accident.)

---

## 2. RTDB data model

### Path
`omok/games/{gameId}` — sibling of `v2/canvases`, never overlapping.

`gameId` = 5 chars from `0123456789abcdefghijklmnopqrstuvwxyz` (lowercase only, unlike `CanvasIDView`'s mixed case — room codes get typed and read aloud, so avoid case ambiguity).

### Schema

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

### Board as a map — recommended over a moves list

| | `board` map (recommended) | `moves` push-list |
|---|---|---|
| Occupancy check | O(1) key existence — expressible directly in a security rule (`!data.exists()`) | Requires scanning all children; not expressible in rules |
| Transaction payload | Whole game node ≤ ~10 KB at 225 stones — trivial | Grows the same, but replay logic needed on every read |
| Client state | `board` *is* the render model; no reconstruction | Must replay in order; ordering bugs on reconnect |
| Convergence | Idempotent — a duplicated write is a no-op | Duplicate push = phantom extra stone |
| History/replay | Not available | Free |

Verdict: **`board` map**. Omok's MVP needs exactly one historical fact — where the last stone landed, for the "last move" marker — and `lastMove` covers that in one field. If move history/replay/takeback is wanted later, add an append-only `moves` push-list *alongside* the map; the map stays the source of truth.

### Key format footgun (do not skip)

Cell keys are **`"{row}_{col}"`** (e.g. `"7_7"`), *not* a flat integer index. RTDB coerces a node whose keys are all numeric into a JSON array on read, which would silently turn `board` into a sparse `NSArray` and break `[String: Any]` decoding. The underscore keeps keys non-numeric.

### Sync shape

One `.value` observer on the entire game node → `AsyncStream<GameState?>`. This deliberately differs from `FirebaseCanvasRepository`'s three child-event observers: the drawing app streams an unbounded firehose, whereas a whole Omok game is a few KB, and whole-node snapshots make turn/status/board mutually consistent by construction (no window where the board advanced but `turn` hasn't). Yields `nil` when the node doesn't exist, which is how "invalid room code" is detected.

### Joining, seat claiming, turn enforcement

**Create** writes the node with `status: "waiting"`, `turn: "black"`, `round: 0`, `moveCount: 0`, and the creator in `players/black`.

**Join** (`claimSeat`) is a transaction on the game node:
1. `currentData.value == nil` → abort with `.gameNotFound` (do **not** create — a typo'd code must fail loudly, not silently open an empty room; this is an intentional divergence from shareddrawing where any canvas ID is valid).
2. If `uid` already occupies a seat → return that color unchanged (**reconnect path — required**, otherwise backgrounding the app locks you out of your own game).
3. Else fill the first empty seat, and if both seats are now filled set `status: "playing"`.
4. Both seats filled by other uids → abort `.gameFull` (the client becomes a read-only spectator).

**Move** (`placeStone`) is a transaction on the game node:
1. Guard `status == "playing"`, `players[turn].uid == uid`, `board["r_c"]` absent.
2. Set the cell, `moveCount += 1`, `lastMove`, flip `turn`.
3. Run `GomokuRules.winningLine(board:lastMove:)`; on a win set `status: "finished"`, `result: <color>`, `winningLine`.
4. Else if `moveCount == 225` set `status: "finished"`, `result: "draw"`.
5. Commit. Two simultaneous taps: RTDB retries the loser's transaction against fresh data, where the guard now fails → surface a benign "not your turn" / "occupied" message.

**Rematch:** each player writes `rematch/{uid}: true`. Whichever client observes both votes runs a reset transaction: `board = nil`, `moveCount = 0`, `result = nil`, `winningLine = nil`, `rematch = nil`, `round += 1`, `status = "playing"`, and `turn = (round % 2 == 0) ? "black" : "white"` so the opening move alternates. Seats stay fixed (they're write-once under the rules), which keeps fairness without mutating `players`.

---

## 3. Game logic (`Shared/GomokuRules.swift`)

Pure, dependency-free, no Firebase import — mirrors `Shared/StrokeHitTesting.swift`.

- `static let size = 15`
- `winningLine(board: [Cell: Stone], from cell: Cell, color: Stone) -> [Cell]?` — for each of the 4 axes (horizontal, vertical, and both diagonals), walk both directions from the placed cell counting contiguous same-color stones; if total ≥ 5, return the 5+ cells. **Free-style rules: overlines (6+) win.**
- `isBoardFull(moveCount:) -> Bool` → `moveCount >= 225`
- `isValid(cell:) -> Bool` → both coords in `0..<15`

Only the just-placed cell is examined, so this is O(1) per move — no full-board scan. Because it's pure it can run inside the transaction body, where re-execution on retry is mandatory.

**Explicitly out of MVP:** renju forbidden moves (double-three, double-four, overline ban), swap2 opening. These are non-trivial and *not* worth attempting now. They are additive later: a `GomokuRules.isForbidden(board:cell:color:) -> Bool` called in the transaction guard before the cell write, plus an optional `variant` field on the game node. Note in the README as a follow-up.

---

## 4. SwiftUI views

**`Features/Lobby/GameIDView.swift`** — root. Mirrors `CanvasIDView`: title, room-code TextField (autocorrection off, no autocapitalization), Create / Join buttons, `navigationDestination` into `GameView`. Adds an alert for "no game with that code" (fed by `listenToGame` yielding `nil`).

**`Features/Game/GameView.swift`** — owns `@State private var viewModel: GameViewModel` constructed in `init` (same pattern as `CanvasView`). Layout: status bar on top, `BoardView` in the middle, action row at the bottom. Overlays: a "Waiting for opponent — share code XXXXX" scrim while `status == "waiting"`, and `ResultBanner` when `status == "finished"`. Claims a seat in `.task`.

**`Features/Game/BoardView.swift`** — one SwiftUI `Canvas` drawing grid lines, star points, stones, a last-move marker, and the highlighted winning line; one tap gesture. Chosen over a 225-button `LazyVGrid` because omok stones sit *on intersections*, not inside cells — a grid of buttons fights that geometry, and 225 views is heavier than one `Canvas`.

Exact geometry (spec this precisely so the implementer doesn't guess):
```
let side = min(size.width, size.height)
let cell = side / 15                  // 15 intersections
func point(_ i: Int) -> CGFloat { cell / 2 + CGFloat(i) * cell }
// tap -> cell
let c = Int(((p.x - cell/2) / cell).rounded())
let r = Int(((p.y - cell/2) / cell).rounded())
// reject if out of 0..<15, or hypot(p - intersectionCenter) > cell * 0.5
```
Stone radius `cell * 0.42`. Board background `Color(red: 0.87, green: 0.72, blue: 0.47)`. Star points at rows/cols {3, 7, 11}. Taps are ignored (no network call) unless `viewModel.canPlay` is true.

**`Features/Game/GameStatusBar.swift`** — room code + share button, "Your turn" / "Opponent's turn" / "Spectating", and your color swatch.

**`Features/Game/ResultBanner.swift`** — "You win" / "You lose" / "Draw" plus a Rematch button showing vote state ("Waiting for opponent…" once you've voted).

---

## 5. RTDB security rules

Deploy as `RTDB_SECURITY_RULES.json` to the new `omok` Firebase project (its own database — no shareddrawing rules to merge).

```json
{
  "rules": {
    "omok": {
      "games": {
        "$gameId": {
          ".read": "auth != null",
          ".write": "auth != null",
          "status":    { ".validate": "newData.isString() && newData.val().matches(/^(waiting|playing|finished)$/)" },
          "turn":      { ".validate": "newData.val() === 'black' || newData.val() === 'white'" },
          "round":     { ".validate": "newData.isNumber() && newData.val() >= 0" },
          "moveCount": { ".validate": "newData.isNumber() && newData.val() >= 0 && newData.val() <= 225" },
          "result":    { ".validate": "newData.val() === 'black' || newData.val() === 'white' || newData.val() === 'draw'" },
          "board": {
            "$cell": {
              ".validate": "$cell.matches(/^[0-9]{1,2}_[0-9]{1,2}$/) && (newData.val() === 'black' || newData.val() === 'white') && (!data.exists() || data.val() === newData.val())"
            }
          },
          "players": {
            "$color": {
              ".validate": "$color === 'black' || $color === 'white'",
              "uid": { ".validate": "newData.isString() && (!data.exists() || data.val() === newData.val() || newData.val() === auth.uid)" },
              "name": { ".validate": "newData.isString() && newData.val().length > 0 && newData.val().length <= 20 && (!data.exists() || data.val() === newData.val() || newData.parent().child('uid').val() === auth.uid)" },
              "joinedAt": { ".validate": "newData.isNumber()" }
            }
          },
          "rematch": {
            "$uid": { ".validate": "$uid === auth.uid && newData.val() === true" }
          }
        }
      }
    }
  }
}
```

Two rule-authoring subtleties the implementer must respect, or legitimate writes will be rejected:

1. **A transaction commits a whole-node `put`, so unchanged children are re-sent and re-validated.** That's why every `.validate` includes an `|| data.val() === newData.val()` escape hatch. A naive `!data.exists()` on `board/$cell` would reject every move after the first.
2. **`.validate` rules are skipped for deletions.** This is what lets the rematch reset delete `board` and `rematch` wholesale.

**Honest limits of this ruleset:** it guarantees cells are never overwritten with a different color and that a seat's `uid` can only ever be set to your own. It does **not** prevent a hostile client from placing two stones in a row, deleting the board mid-game, or writing a bogus `result` — those invariants live in the client transaction only. Airtight enforcement needs Cloud Functions (or `moves`-as-append-only with a function-maintained board), which is out of scope. This is still strictly stronger than shareddrawing's deployed `.read: true / .write: true`. If rule debugging becomes a time sink during implementation, fall back to bare `".read": "auth != null", ".write": "auth != null"` and ship.

---

## 6. Implementation steps (dependency order)

| # | Step | Tier |
|---|---|---|
| 1 | Create `Omok.xcodeproj`: app target, iOS 17.0 / Swift 5.9, bundle `io.github.nicechester.omok`, generated Info.plist keys, portrait-only, and `PBXFileSystemSynchronizedRootGroup`s for `Core`/`Features`/`Shared`. Add SPM `firebase-ios-sdk` ≥ 12.16.0 with `FirebaseAuth` + `FirebaseDatabase`. Add `Assets.xcassets` + `Preview Content`. Verify it builds empty. Hand-authoring a pbxproj with synchronized groups is error-prone — do not delegate down. | **[senior]** |
| 2 | Write `README.md` + `CLAUDE.md` (stack, `omok/games` schema, Firebase console steps: create new `omok` project, add iOS app, enable Anonymous Auth, create RTDB instance, drop plist at repo root, deploy rules) and `.gitignore` (`GoogleService-Info.plist`, `build/`, `*.xcuserdatad`). Console clicks + plist download are a human action — document them as prerequisites. | **[junior]** |
| 3 | `Core/Models/`: `Stone.swift` (`enum Stone: String { black, white }` + `var opposite`), `Cell.swift` (`struct Cell: Hashable, Codable { let r, c: Int }` + `var key: String { "\(r)_\(c)" }` + `init?(key:)`), `GameState.swift` (`GameStatus`, `GameResult`, `GameState` with `board: [Cell: Stone]`, `lastMove`, `players`, `rematchVotes: Set<String>`, `round`, `moveCount`, plus `func seat(of uid: String) -> Stone?`). No Firebase imports. | **[junior]** |
| 4 | `Shared/GomokuRules.swift`: `size`, `isValid(cell:)`, `winningLine(board:from:color:)` (4 axes, ≥5 contiguous, overlines win), `isBoardFull(moveCount:)`. Pure. Off-by-one and diagonal-direction errors here are silent gameplay bugs. | **[senior]** |
| 5 | `AuthService.swift` at target root: port shareddrawing's `@Observable AuthService` but strip Google sign-in — keep `currentUserID`, `isAuthenticated`, the `addStateDidChangeListener` setup, `signInAnonymously()`, `deinit` listener removal. Delete `signInWithGoogle`, `signOut`, `topViewController`, `AuthError` cases, and the `GoogleSignIn`/`UIKit` imports. | **[junior]** |
| 6 | `Core/Networking/GameRepository.swift` — protocol: `listenToGame(gameId:) -> AsyncStream<GameState?>`, `createGame(gameId:creatorUid:) async throws`, `claimSeat(gameId:uid:) async throws -> Stone`, `placeStone(gameId:at:uid:) async throws`, `voteRematch(gameId:uid:) async throws`, `resetForRematch(gameId:) async throws`; plus `enum GameError: LocalizedError { gameNotFound, gameFull, notYourTurn, cellOccupied, gameNotActive }`. | **[senior]** |
| 7 | `Core/Networking/FirebaseGameRepository.swift` — `.value` observer → `AsyncStream<GameState?>` with `continuation.onTermination` teardown (mirroring `FirebaseCanvasRepository.listenToStrokes`); snapshot ⇄ dictionary codecs for the `omok/games/{id}` schema; all four mutations as `runTransactionBlock` wrapped in `withCheckedThrowingContinuation` (the Firebase SDK has no async transaction overload); `GomokuRules` invoked inside `placeStone`'s transaction body. The riskiest file in the project. | **[senior]** |
| 8 | `Core/Networking/FakeGameRepository.swift` — in-memory `GameRepository` for previews and unit tests (shareddrawing's pbxproj references a `FakeCanvasRepository.swift` that doesn't exist on disk; actually create this one). | **[junior]** |
| 9 | `Features/Game/GameViewModel.swift` — `@Observable`, holds `game: GameState?`, `mySeat: Stone?`, `errorMessage`; derives `canPlay`, `isSpectator`, `statusText`, `isMyWin`; `claimSeat()`, `place(cell:)`, `requestRematch()`; listener `Task` cancelled in `deinit`; auto-triggers `resetForRematch` when both votes are observed (guarded so both clients racing is harmless). | **[senior]** |
| 10 | `Features/Game/BoardView.swift` — single `Canvas` (grid, star points, stones, last-move marker, winning-line highlight) + tap→cell mapping using the exact geometry above; ignores taps unless `canPlay`. | **[junior]** |
| 11 | `Features/Game/GameStatusBar.swift` + `ResultBanner.swift` — presentation only, driven by `GameViewModel` derived properties. | **[junior]** |
| 12 | `Features/Game/GameView.swift` — composes status bar / board / actions, waiting-for-opponent overlay, result banner, `.task { await viewModel.claimSeat() }`, error alert. Constructs the ViewModel in `init` like `CanvasView`. | **[junior]** |
| 13 | `Features/Lobby/GameIDView.swift` — port `CanvasIDView`: code field, Create (5 lowercase chars) / Join, `navigationDestination` to `GameView`, invalid-code alert. | **[junior]** |
| 14 | `OmokApp.swift` — `FirebaseApp.configure()` in `init`, `@State authService`, `ProgressView("Initializing...")` gate awaiting `signInAnonymously()`, then `GameIDView`. No `onOpenURL`, no `GIDSignIn`. | **[junior]** |
| 15 | `RTDB_SECURITY_RULES.json` — merged `v2` + `omok` ruleset exactly as above, and document `firebase deploy --only database` in the README. | **[junior]** |
| 16 | Optional `OmokTests` target + `GomokuRulesTests.swift` (horizontal/vertical/both diagonals, edges and corners, overline, blocked-4 negative case, full-board draw) and a `GameViewModelTests` using `FakeGameRepository`. Requires a pbxproj target addition. | **[senior]** |
| 17 | Manual end-to-end on two simulators: create on A, join by code on B, alternate moves, verify win banner on both, rematch, then hammer simultaneous taps on the same cell. Human/verification step. | — |

Steps 3–5 are independent and can run in parallel after step 1. Step 15 must be deployed before step 17.

---

## Edge cases the implementer must handle

1. **Transaction bodies run multiple times and may first run against a `nil` local cache.** `currentData.value == nil` must `.abort()`, never create the node — otherwise a typo'd room code silently materializes an empty game.
2. **`ServerValue.timestamp()` inside a transaction** resolves server-side; the local run sees a sentinel dictionary. Never read a timestamp inside transaction logic. Use `Int(Date().timeIntervalSince1970 * 1000)` for `updatedAt` inside transactions; reserve `ServerValue.timestamp()` for the non-transactional create.
3. **Numeric board keys** → RTDB array coercion. Keys must be `"7_7"`, never `"112"`.
4. **Whole-node put re-validates unchanged children** — every `.validate` needs the `data.val() === newData.val()` escape hatch (§5).
5. **Reconnect must return your existing seat**, not `.gameFull`. Backgrounding, force-quitting, or re-navigating all hit this path.
6. **Same uid holding both seats** — reject in `claimSeat`. Each simulator has its own anonymous uid so two-simulator testing is unaffected, but a rebuilt app can reuse a uid.
7. **Third participant** — no seat available → spectator: full read, taps inert, status bar says "Spectating".
8. **Simultaneous taps on the same cell** — the losing transaction fails its guard; surface a transient message, never crash or leave a phantom stone.
9. **Draw at exactly 225** — must be checked *after* the win check, so a winning 225th stone is a win, not a draw.
10. **Listener lifetime** — cancel the `Task` and let `onTermination` remove observers on navigating back, or a stale game keeps streaming.
11. **Rematch double-vote race** — both clients may observe the second vote and both fire `resetForRematch`; the reset transaction must be idempotent (guard on `status == "finished"`).
12. **RTDB disk persistence stays off** (SDK default), matching shareddrawing. Enabling it would serve stale boards from cache on launch.

---

## Out of scope

AI opponent. Matchmaking beyond join-by-code. Game history / archived games (only the live game node exists). Renju forbidden-move rules and swap2 openings (noted as an additive follow-up in §3). Move clocks / timeouts. Presence and disconnect-forfeit. Takeback/undo. Chat. Deep links and Universal Links (shareddrawing's `onOpenURL` + associated-domains entitlement are deliberately not ported). Google Sign-In and account linking. iPad-specific layout. Cloud Functions server-authoritative validation.

Nothing under `shareddrawing/` is touched by this plan — Omok runs on its own Firebase project with its own database and ruleset.

# Omok (오목)

A real-time collaborative two-player five-in-a-row game for iOS, built with SwiftUI and Firebase Realtime Database.

## What is Omok?

Omok (오목) is a classic board game where two players take turns placing stones on a 15×15 grid, trying to align five of their stones in a row (horizontally, vertically, or diagonally). This is the digital version: two players connect via a 5-character room code and play in real-time with instant synchronization.

**Technology**: SwiftUI, Firebase Realtime Database, async/await, MVVM + Repository pattern.

## How to Play

1. Open the app — you'll be asked to create or join a game
2. **Create a game**: Generate a 5-character lowercase room code (e.g., `abc12`), and you'll be seated as Black (first move)
3. **Join a game**: Enter the room code to join as White
4. Take turns placing stones on intersections; first to line up five wins
5. After the game ends, either player can propose a rematch

Players alternate colors automatically on rematch to ensure fairness.

**Player nicknames:** Set your nickname on first run and change it anytime via the gear icon in the lobby — your opponent sees it in the status bar.

## Firebase Setup (Required Before First Run)

Before you can run the app, you must set up a dedicated Firebase project. These are **console actions** — not code:

1. **Create a Firebase project** at [console.firebase.google.com](https://console.firebase.google.com)
   - Click "Add project", name it (e.g., `omok`), and complete the wizard

2. **Add an iOS app** to the project
   - In the Firebase Console, click "Add app" → iOS
   - Enter the bundle ID: `io.github.nicechester.omok`
   - Download the `GoogleService-Info.plist` file and **save it to the repo root** (same folder as `Omok.xcodeproj`)

3. **Enable Anonymous Authentication**
   - Go to Authentication → Sign-in method
   - Enable the "Anonymous" provider

4. **Create a Realtime Database instance**
   - Go to Realtime Database → Create Database
   - Choose the location nearest to you
   - Start in test mode (we'll lock it down in the next step)

5. **Deploy security rules**
   - In Realtime Database, go to the Rules tab
   - Replace the content with the rules from `RTDB_SECURITY_RULES.json`
   - Click Publish

Once `GoogleService-Info.plist` is in place and the database is running, build and run the app on iOS 17+.

## Architecture

- **iOS 17+** with SwiftUI
- **Firebase Realtime Database** for real-time game state sync
- **Swift Package Manager** for dependencies (Firebase SDK only)
- **MVVM + Repository pattern** with async/await and `AsyncStream`
- **Core / Features / Shared** folder structure (as in shareddrawing)

Game mutations are atomic RTDB transactions on the game node, ensuring no race conditions on concurrent move placement.

## Follow-Ups / Out of Scope

These features are **not** in the MVP but could be added later:

- **Renju rules** — Forbidden moves (double-three, double-four, overline bans)
- **Move history & replay** — View past games; undo/takeback within a game
- **AI opponent** — Single-player mode with a bot
- **Presence & timeouts** — See when players are online; forfeit after inactivity
- **Chat** — Communicate with your opponent
- **Deep links & Universal Links** — Share game codes via URL

## Development

See [CLAUDE.md](./CLAUDE.md) for architecture details, the full RTDB schema, security model, and implementation guidelines.

## License

TBD

import SwiftUI
import Firebase

@main
struct OmokApp: App {
    @State private var authService: AuthService
    @State private var isInitialized = false
    @AppStorage(PlayerName.storageKey) private var playerName = ""

    init() {
        FirebaseApp.configure()
        _authService = State(initialValue: AuthService())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if isInitialized, let uid = authService.currentUserID {
                    if !PlayerName.isValid(playerName) {
                        NavigationStack {
                            NicknameView(isFirstRun: true)
                        }
                    } else {
                        NavigationStack {
                            GameIDView(uid: uid)
                        }
                    }
                } else {
                    ProgressView("Initializing...")
                        .task {
                            try? await authService.signInAnonymously()
                            isInitialized = true
                        }
                }
            }
        }
    }
}

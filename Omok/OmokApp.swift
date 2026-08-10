import SwiftUI
import Firebase
import UserNotifications

@main
struct OmokApp: App {
    @State private var authService: AuthService
    @State private var isInitialized = false
    @State private var pendingGameCode: String?
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
                        RootTabView(uid: uid, pendingGameCode: $pendingGameCode)
                            .task {
                                // Check for pending game ID from notification
                                if let gameId = NotificationManager.shared.pendingGameId {
                                    pendingGameCode = gameId
                                    NotificationManager.shared.pendingGameId = nil
                                }
                            }
                    }
                } else {
                    ProgressView("Initializing...")
                        .task {
                            // Initialize NotificationManager on the main actor
                            _ = NotificationManager.shared
                            try? await authService.signInAnonymously()
                            isInitialized = true
                        }
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("omokOpenGame"))) { notification in
                if let gameId = notification.userInfo?["gameId"] as? String {
                    pendingGameCode = gameId
                }
            }
        }
    }
    
    private func handleDeepLink(_ url: URL) {
        // Handle omok://join?code=abc12
        guard url.scheme == "omok",
              url.host == "join" else {
            return
        }
        
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
           let code = components.queryItems?.first(where: { $0.name == "code" })?.value,
           !code.isEmpty {
            pendingGameCode = code
        }
    }
}

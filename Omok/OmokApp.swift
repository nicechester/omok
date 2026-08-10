import SwiftUI
import Firebase

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
                    }
                } else {
                    ProgressView("Initializing...")
                        .task {
                            try? await authService.signInAnonymously()
                            isInitialized = true
                        }
                }
            }
            .onOpenURL { url in
                handleDeepLink(url)
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

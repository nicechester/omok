import SwiftUI
import Firebase
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Messaging.messaging().delegate = self
        application.registerForRemoteNotifications()
        return true
    }
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }
    
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let token = fcmToken else { return }
        Task { @MainActor in
            NotificationManager.shared.fcmToken = token
        }
    }
}

@main
struct OmokApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
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
                            // Request notification permission if enabled in settings
                            if NotificationSettings.isEnabled {
                                _ = await NotificationManager.shared.requestAuthorization()
                            }
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

import SwiftUI
import Firebase
import FirebaseMessaging
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate, MessagingDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Messaging.messaging().delegate = self
        application.registerForRemoteNotifications()

        // Set up notification delegate early
        UNUserNotificationCenter.current().delegate = NotificationManager.shared

        // Handle cold start notification tap
        if let remoteNotification = launchOptions?[UIApplication.LaunchOptionsKey.remoteNotification] as? [AnyHashable: Any],
           let gameId = remoteNotification["gameId"] as? String {
            Task { @MainActor in
                NotificationManager.shared.pendingGameId = gameId
            }
        }

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
    @State private var pendingGameCode: String?
    @AppStorage(PlayerName.storageKey) private var playerName = ""

    init() {
        FirebaseApp.configure()
        _authService = State(initialValue: AuthService())
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let uid = authService.currentUserID {
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
                    LaunchStatusView(
                        status: authService.connectionStatus,
                        onRetry: {
                            Task {
                                await authService.signInAnonymously()
                            }
                        }
                    )
                    .task {
                        async let notif: Void = requestNotificationPermissionIfNeeded()
                        async let signIn: Void = authService.signInAnonymously()
                        _ = await (notif, signIn)
                    }
                }
            }
            .environment(authService)
            .onOpenURL { url in
                handleDeepLink(url)
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                handleUniversalLink(url)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("omokOpenGame"))) { notification in
                if let gameId = notification.userInfo?["gameId"] as? String {
                    pendingGameCode = gameId
                }
            }
        }
    }

    private func requestNotificationPermissionIfNeeded() async {
        if NotificationSettings.isEnabled {
            _ = await NotificationManager.shared.requestAuthorization()
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

    private func handleUniversalLink(_ url: URL) {
        // Handle https://omok-5-in-a-row.web.app/join/{code}
        guard url.host == "omok-5-in-a-row.web.app" else { return }
        let components = url.pathComponents
        if let joinIndex = components.firstIndex(of: "join"),
           components.indices.contains(joinIndex + 1) {
            let code = components[joinIndex + 1]
            if !code.isEmpty { pendingGameCode = code }
        }
    }
}

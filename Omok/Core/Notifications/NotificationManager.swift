import Foundation
import UIKit
import UserNotifications
import Observation
import FirebaseDatabase
import FirebaseAuth

@MainActor
@Observable
final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()

    var authorizationStatus: UNAuthorizationStatus = .notDetermined
    var pendingGameId: String?
    var fcmToken: String? {
        didSet {
            if let token = fcmToken {
                saveTokenToDatabase(token)
            }
        }
    }
    
    private func saveTokenToDatabase(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        Database.database().reference()
            .child("omok/users").child(uid).child("fcmToken")
            .setValue(token)
    }

    private override init() {
        super.init()
        Task {
            await checkAuthorizationStatus()
            UNUserNotificationCenter.current().delegate = self
        }
    }

    // MARK: - Authorization

    private func checkAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            await checkAuthorizationStatus()
            return granted
        } catch {
            return false
        }
    }

    // MARK: - Scheduling

    func scheduleGameNotification(
        gameId: String,
        title: String,
        body: String
    ) async {
        guard NotificationSettings.isEnabled else { return }
        guard authorizationStatus == .authorized else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.badge = NSNumber(value: UIApplication.shared.applicationIconBadgeNumber + 1)
        content.threadIdentifier = gameId
        content.userInfo = ["gameId": gameId]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: trigger
        )

        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            print("Failed to schedule notification: \(error)")
        }
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        if let gameId = userInfo["gameId"] as? String {
            Task { @MainActor in
                NotificationManager.shared.pendingGameId = gameId
            }
            NotificationCenter.default.post(
                name: NSNotification.Name("omokOpenGame"),
                object: nil,
                userInfo: ["gameId": gameId]
            )
        }
        completionHandler()
    }
}

extension NotificationSettings {
    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}

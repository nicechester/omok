import SwiftUI
import UserNotifications

struct SettingsView: View {
    @AppStorage(NotificationSettings.storageKey) private var notificationsEnabled = true
    @AppStorage(AudioOutputSettings.storageKey) private var audioOutputLevel = AudioOutputSettings.defaultLevel.rawValue
    @State private var authorizationStatus: UNAuthorizationStatus = .notDetermined

    var body: some View {
        NavigationStack {
            List {
                Section("Notifications") {
                    Toggle("Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, newValue in
                            if newValue {
                                Task {
                                    _ = await NotificationManager.shared.requestAuthorization()
                                    await updateAuthorizationStatus()
                                }
                            }
                        }
                    if authorizationStatus == .denied {
                        Label(
                            "Off in iOS Settings",
                            systemImage: "exclamationmark.circle.fill"
                        )
                        .foregroundColor(.orange)
                        .font(.caption)
                    }
                }

                Section("Audio") {
                    Picker("Opponent Volume", selection: $audioOutputLevel) {
                        ForEach(AudioOutputSettings.VolumeLevel.allCases, id: \.self) { level in
                            Text(level.label).tag(level.rawValue)
                        }
                    }
                }

                Section {
                    NicknameView(isFirstRun: false)
                }
            }
            .onAppear {
                Task {
                    await updateAuthorizationStatus()
                }
            }
        }
    }

    private func updateAuthorizationStatus() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

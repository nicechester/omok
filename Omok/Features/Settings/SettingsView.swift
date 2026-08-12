import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(AuthService.self) private var authService
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

                Section("Connection") {
                    HStack {
                        ConnectionStatusIndicator(status: authService.connectionStatus, size: .small)

                        switch authService.connectionStatus {
                        case .connecting:
                            Text("Connecting…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .connected:
                            Text("Connected")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        case .error:
                            Text("Connection Error")
                                .font(.caption)
                                .foregroundColor(.red)
                        }

                        Spacer()
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
    let authService = AuthService()
    return NavigationStack {
        SettingsView()
            .environment(authService)
    }
}

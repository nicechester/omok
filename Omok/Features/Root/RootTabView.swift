import SwiftUI

struct RootTabView: View {
    let uid: String
    @Binding var pendingGameCode: String?
    @State private var selectedTab = 1
    @State private var activeGameId: String?
    @State private var aiDifficulty: AIDifficulty?
    @State private var timerDuration: Int?

    init(uid: String, pendingGameCode: Binding<String?>) {
        self.uid = uid
        self._pendingGameCode = pendingGameCode
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                RoomsView(uid: uid, onJoinRoom: { code, difficulty, timer in
                    aiDifficulty = difficulty
                    timerDuration = timer
                    activeGameId = code
                    selectedTab = 2
                })
            }
            .tabItem { Label("Rooms", systemImage: "list.bullet") }
            .tag(1)

            PlayView(uid: uid, activeGameId: $activeGameId, aiDifficulty: $aiDifficulty, pendingGameCode: $pendingGameCode, timerDuration: $timerDuration)
                .tabItem { Label("Play", image: "omok-bh") }
                .tag(2)

            NavigationStack {
                HelpView()
            }
            .tabItem { Label("Help", systemImage: "questionmark.circle") }
            .tag(3)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(4)
        }
        .onChange(of: pendingGameCode) { _, newCode in
            if let code = newCode {
                activeGameId = code
                pendingGameCode = nil
                selectedTab = 2
            }
        }
    }
}

#Preview {
    RootTabView(uid: "user1", pendingGameCode: .constant(nil))
}

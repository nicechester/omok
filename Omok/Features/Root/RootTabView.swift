import SwiftUI

struct RootTabView: View {
    let uid: String
    @Binding var pendingGameCode: String?
    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @State private var selectedTab = 1
    @State private var selectedGameId: String?

    init(uid: String, pendingGameCode: Binding<String?>) {
        self.uid = uid
        self._pendingGameCode = pendingGameCode
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        NavigationStack(path: Binding(
            get: { selectedGameId.map { [$0] } ?? [] },
            set: {
                if let first = $0.first {
                    selectedGameId = first
                } else {
                    selectedGameId = nil
                }
            }
        )) {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    RoomsView(uid: uid)
                }
                .tabItem {
                    Label("Rooms", systemImage: "list.bullet")
                }
                .tag(1)

                NavigationStack {
                    PlayView(uid: uid, pendingGameCode: $pendingGameCode)
                }
                .tabItem {
                    Label("Play", image: "omok-bh")
                }
                .tag(2)

                NavigationStack {
                    SettingsView()
                }
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
            }
            .navigationDestination(for: String.self) { gameId in
                GameView(gameId: gameId, uid: uid, playerName: playerName, onLeave: { selectedGameId = nil })
                    .navigationBarBackButtonHidden()
            }
        }
        .onChange(of: pendingGameCode) { _, newCode in
            if let code = newCode {
                selectedGameId = code
                pendingGameCode = nil
            }
        }
    }
}

#Preview {
    RootTabView(uid: "user1", pendingGameCode: .constant(nil))
}

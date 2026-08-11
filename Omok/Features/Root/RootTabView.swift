import SwiftUI

struct RootTabView: View {
    let uid: String
    @Binding var pendingGameCode: String?
    @State private var selectedTab = 1
    @State private var activeGameId: String?

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
                RoomsView(uid: uid, onJoinRoom: { code in
                    activeGameId = code
                    selectedTab = 2
                })
            }
            .tabItem { Label("Rooms", systemImage: "list.bullet") }
            .tag(1)

            PlayView(uid: uid, activeGameId: $activeGameId, pendingGameCode: $pendingGameCode)
                .tabItem { Label("Play", image: "omok-bh") }
                .tag(2)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
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

import SwiftUI

struct RootTabView: View {
    let uid: String

    init(uid: String) {
        self.uid = uid
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    var body: some View {
        TabView {
            NavigationStack {
                RoomsView(uid: uid)
            }
            .tabItem {
                Label("Rooms", systemImage: "list.bullet")
            }

            NavigationStack {
                PlayView(uid: uid)
            }
            .tabItem {
                Label("Play", image: "omok-bh")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

#Preview {
    RootTabView(uid: "user1")
}

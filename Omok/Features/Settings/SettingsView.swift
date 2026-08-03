import SwiftUI

struct SettingsView: View {
    var body: some View {
        NicknameView(isFirstRun: false)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}

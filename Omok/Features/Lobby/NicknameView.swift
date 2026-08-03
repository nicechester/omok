import SwiftUI

struct NicknameView: View {
    let isFirstRun: Bool

    @AppStorage(PlayerName.storageKey) private var storedName = ""
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 20) {
            Text(isFirstRun ? "Choose a nickname" : "Change nickname")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                TextField("Nickname", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onChange(of: draft) { _, newValue in
                        if newValue.utf16.count > PlayerName.maxLength {
                            draft = String(newValue.prefix(PlayerName.maxLength))
                        }
                    }
                Text("\(draft.count)/\(PlayerName.maxLength)")
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Button(action: {
                storedName = PlayerName.sanitize(draft)
            }) {
                Text("Save")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!PlayerName.isValid(draft))

            Spacer()
        }
        .padding()
        .navigationTitle("Nickname")
        .onAppear {
            draft = storedName
        }
    }
}

#Preview("First Run") {
    NavigationStack {
        NicknameView(isFirstRun: true)
    }
}

#Preview("Settings") {
    NavigationStack {
        NicknameView(isFirstRun: false)
    }
}

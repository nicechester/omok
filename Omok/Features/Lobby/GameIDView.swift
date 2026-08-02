import SwiftUI

struct GameIDView: View {
    let uid: String

    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @State private var enteredCode = ""
    @State private var selectedGameId: String?
    @State private var isCreator = false
    @State private var showNicknameSheet = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Omok 오목")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Playing as \(playerName)")
                    .font(.subheadline)
                    .foregroundColor(.gray)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Room Code")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    TextField("Enter room code", text: $enteredCode)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onChange(of: enteredCode) { _, newValue in
                            // Force lowercase and alphanumeric only
                            enteredCode = newValue
                                .lowercased()
                                .filter { $0.isLetter || $0.isNumber }
                        }
                }

                HStack(spacing: 12) {
                    Button(action: {
                        selectedGameId = generateRandomCode()
                        isCreator = true
                    }) {
                        Text("Create")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)

                    Button(action: {
                        let trimmed = enteredCode.trimmingCharacters(in: .whitespaces)
                        if !trimmed.isEmpty {
                            selectedGameId = trimmed
                            isCreator = false
                        }
                    }) {
                        Text("Join")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(enteredCode.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: .constant(selectedGameId != nil)) {
                if let gameId = selectedGameId {
                    GameView(gameId: gameId, isCreator: isCreator, uid: uid, playerName: playerName)
                        .navigationBarBackButtonHidden()
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showNicknameSheet = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showNicknameSheet) {
                NavigationStack {
                    NicknameView(isFirstRun: false)
                }
            }
        }
    }

    private func generateRandomCode() -> String {
        let characters = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<5).map { _ in characters.randomElement()! })
    }
}

import SwiftUI

struct GameIDView: View {
    let uid: String

    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @State private var roomCode = ""
    @State private var selectedGameId: String?
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
                    TextField("Room code", text: $roomCode)
                        .textFieldStyle(.roundedBorder)
                        .font(.title3)
                        .fontWeight(.semibold)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .monospaced()
                        .onChange(of: roomCode) { _, newValue in
                            // Force lowercase and alphanumeric only
                            roomCode = newValue
                                .lowercased()
                                .filter { $0.isLetter || $0.isNumber }
                                .prefix(5)
                                .description
                        }
                }

                Button(action: {
                    let trimmed = roomCode.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty {
                        selectedGameId = trimmed
                    }
                }) {
                    Text("Join Game")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(roomCode.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding()
            .navigationDestination(isPresented: .constant(selectedGameId != nil)) {
                if let gameId = selectedGameId {
                    GameView(gameId: gameId, uid: uid, playerName: playerName)
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
            .onAppear {
                if roomCode.isEmpty {
                    roomCode = generateRandomCode()
                }
            }
        }
    }

    private func generateRandomCode() -> String {
        let characters = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<5).map { _ in characters.randomElement()! })
    }
}

import SwiftUI

struct PlayView: View {
    let uid: String
    @Binding var pendingGameCode: String?

    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @State private var roomCode = ""
    @State private var selectedGameId: String?

    var body: some View {
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
        .navigationDestination(isPresented: Binding(
            get: { selectedGameId != nil },
            set: { if !$0 { selectedGameId = nil } }
        )) {
            if let gameId = selectedGameId {
                GameView(gameId: gameId, uid: uid, playerName: playerName, onLeave: { selectedGameId = nil })
                    .navigationBarBackButtonHidden()
            }
        }
        .onAppear {
            if roomCode.isEmpty {
                roomCode = generateRandomCode()
            }
        }
        .onChange(of: pendingGameCode) { _, newCode in
            if let code = newCode {
                roomCode = code
                selectedGameId = code
                pendingGameCode = nil
            }
        }
    }

    private func generateRandomCode() -> String {
        let characters = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<5).map { _ in characters.randomElement()! })
    }
}

#Preview {
    NavigationStack {
        PlayView(uid: "user1", pendingGameCode: .constant(nil))
    }
}

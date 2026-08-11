import SwiftUI

struct PlayView: View {
    let uid: String
    @Binding var pendingGameCode: String?

    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @AppStorage(TurnTimer.storageKey) private var timerDurationPreference = 0
    @State private var roomCode = ""
    @State private var selectedGameId: String?
    @FocusState private var isRoomCodeFocused: Bool

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
                    .focused($isRoomCodeFocused)
                    .submitLabel(.done)
                    .onSubmit {
                        isRoomCodeFocused = false
                    }
                    .onChange(of: roomCode) { _, newValue in
                        roomCode = newValue
                            .lowercased()
                            .filter { $0.isLetter || $0.isNumber }
                            .prefix(5)
                            .description
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Turn Timer")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                Picker("Turn Timer", selection: $timerDurationPreference) {
                    Text("Off").tag(0)
                    Text("10s").tag(10)
                    Text("20s").tag(20)
                    Text("30s").tag(30)
                    Text("60s").tag(60)
                }
                .pickerStyle(.segmented)
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
        .contentShape(Rectangle())
        .onTapGesture {
            isRoomCodeFocused = false
        }
        .navigationDestination(isPresented: Binding(
            get: { selectedGameId != nil },
            set: { if !$0 { selectedGameId = nil } }
        )) {
            if let gameId = selectedGameId {
                GameView(
                    gameId: gameId,
                    uid: uid,
                    playerName: playerName,
                    onLeave: { selectedGameId = nil },
                    timerDuration: timerDurationPreference == 0 ? nil : timerDurationPreference
                )
                    .navigationBarBackButtonHidden()
            }
        }
        .onAppear {
            if pendingGameCode == nil && roomCode.isEmpty {
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

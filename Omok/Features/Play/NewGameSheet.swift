import SwiftUI

struct NewGameSheet: View {
    let uid: String
    let onJoin: (String) -> Void

    @AppStorage(TurnTimer.storageKey) private var timerDurationPreference = 0
    @State private var roomCode = ""
    @State private var isExistingGame = false
    @State private var existingTimerDuration: Int?
    @FocusState private var isRoomCodeFocused: Bool
    private let repository = FirebaseGameRepository()

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
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
                        .onSubmit { isRoomCodeFocused = false }
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
                    if isExistingGame {
                        Text(existingTimerDuration.map { "\($0)s (set by room creator)" } ?? "Off (set by room creator)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Turn Timer", selection: $timerDurationPreference) {
                            Text("Off").tag(0)
                            Text("10s").tag(10)
                            Text("20s").tag(20)
                            Text("30s").tag(30)
                            Text("60s").tag(60)
                        }
                        .pickerStyle(.segmented)
                    }
                }

                Button {
                    let trimmed = roomCode.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { onJoin(trimmed) }
                } label: {
                    Text("Join Game")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(roomCode.trimmingCharacters(in: .whitespaces).isEmpty)

                Spacer()
            }
            .padding()
            .navigationTitle("New Game")
            .navigationBarTitleDisplayMode(.inline)
            .contentShape(Rectangle())
            .onTapGesture { isRoomCodeFocused = false }
            .onAppear { roomCode = generateRandomCode() }
            .task(id: roomCode) {
                let code = roomCode.trimmingCharacters(in: .whitespaces)
                guard code.count == 5 else {
                    isExistingGame = false
                    existingTimerDuration = nil
                    return
                }
                try? await Task.sleep(nanoseconds: 400_000_000)
                if Task.isCancelled { return }
                do {
                    if let game = try await repository.fetchGame(gameId: code) {
                        isExistingGame = true
                        existingTimerDuration = game.timerDuration
                    } else {
                        isExistingGame = false
                        existingTimerDuration = nil
                    }
                } catch {
                    isExistingGame = false
                    existingTimerDuration = nil
                }
            }
        }
    }

    private func generateRandomCode() -> String {
        let characters = "0123456789abcdefghijklmnopqrstuvwxyz"
        return String((0..<5).map { _ in characters.randomElement()! })
    }
}

#Preview {
    NewGameSheet(uid: "user1", onJoin: { _ in })
}

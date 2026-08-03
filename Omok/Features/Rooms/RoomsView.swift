import SwiftUI

struct RoomsView: View {
    let uid: String

    @AppStorage(PlayerName.storageKey) private var playerName = ""
    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @State private var selectedGameId: String?

    private var rooms: [RecentRoom] {
        RecentRooms.decode(from: recentRoomsData)
    }

    var body: some View {
        Group {
            if rooms.isEmpty {
                ContentUnavailableView("No Recent Rooms", systemImage: "list.bullet", description: Text("Rooms you play will appear here"))
            } else {
                List(rooms) { room in
                    Button {
                        selectedGameId = room.code
                    } label: {
                        HStack {
                            Text(room.code)
                                .font(.title3)
                                .fontWeight(.semibold)
                                .monospaced()
                            Spacer()
                            Text(room.lastPlayedAt, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Recent Rooms")
        .navigationDestination(isPresented: Binding(
            get: { selectedGameId != nil },
            set: { if !$0 { selectedGameId = nil } }
        )) {
            if let gameId = selectedGameId {
                GameView(gameId: gameId, uid: uid, playerName: playerName, onLeave: { selectedGameId = nil })
                    .navigationBarBackButtonHidden()
            }
        }
    }
}

#Preview {
    NavigationStack {
        RoomsView(uid: "user1")
    }
}

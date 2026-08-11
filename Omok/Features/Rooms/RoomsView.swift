import SwiftUI
import FirebaseDatabase

struct RoomsView: View {
    let uid: String
    let onJoinRoom: (String) -> Void

    @AppStorage(RecentRooms.storageKey) private var recentRoomsData = Data()
    @Environment(\.scenePhase) private var scenePhase

    private struct PendingDeletion {
        let room: RecentRoom
        let restoreIndex: Int
    }

    private let repository = FirebaseGameRepository()
    @State private var pendingDeletion: PendingDeletion?
    @State private var pendingDeleteTask: Task<Void, Never>?
    @State private var showNewGame = false

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
                        onJoinRoom(room.code)
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
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteRoom(room)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
        .overlay(alignment: .bottom) {
            if let pending = pendingDeletion {
                HStack {
                    Text("Room \(pending.room.code.uppercased()) deleted")
                        .font(.subheadline)
                    Spacer()
                    Button("Undo") { undoDelete() }
                        .fontWeight(.semibold)
                }
                .padding()
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .padding()
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Recent Rooms")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showNewGame = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New Game")
            }
        }
        .sheet(isPresented: $showNewGame) {
            NewGameSheet(uid: uid, onJoin: { code in
                showNewGame = false
                onJoinRoom(code)
            })
        }
        .task {
            await syncRecentRoomsWithFirebase()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                Task {
                    await syncRecentRoomsWithFirebase()
                }
            }
        }
    }

    private func deleteRoom(_ room: RecentRoom) {
        // Finalize any earlier pending delete before starting a new one
        if let previous = pendingDeletion {
            pendingDeleteTask?.cancel()
            Task { try? await repository.deleteGame(gameId: previous.room.code, uid: uid) }
        }

        let index = RecentRooms.decode(from: recentRoomsData).firstIndex(where: { $0.code == room.code }) ?? 0
        withAnimation {
            recentRoomsData = RecentRooms.remove(code: room.code, from: recentRoomsData)
            pendingDeletion = PendingDeletion(room: room, restoreIndex: index)
        }

        pendingDeleteTask = Task {
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            await finalizeDelete(gameId: room.code)
        }
    }

    private func undoDelete() {
        guard let pending = pendingDeletion else { return }
        pendingDeleteTask?.cancel()
        pendingDeleteTask = nil
        withAnimation {
            recentRoomsData = RecentRooms.restore(pending.room, at: pending.restoreIndex, in: recentRoomsData)
            pendingDeletion = nil
        }
    }

    private func finalizeDelete(gameId: String) async {
        defer { pendingDeletion = nil; pendingDeleteTask = nil }
        // Best-effort: local list is already correct regardless of outcome.
        try? await repository.deleteGame(gameId: gameId, uid: uid)
    }

    private func gameExists(_ gameId: String) async -> Bool {
        do {
            let snapshot = try await Database.database().reference()
                .child("omok/games").child(gameId)
                .getData()
            return snapshot.exists()
        } catch {
            return true  // On error, assume it exists (don't accidentally delete from list)
        }
    }

    private func syncRecentRoomsWithFirebase() async {
        var rooms = RecentRooms.decode(from: recentRoomsData)
        var needsUpdate = false

        for room in rooms {
            let exists = await gameExists(room.code)
            if !exists {
                rooms.removeAll { $0.code == room.code }
                needsUpdate = true
            }
        }

        if needsUpdate {
            recentRoomsData = RecentRooms.encode(rooms)
        }
    }
}

#Preview {
    NavigationStack {
        RoomsView(uid: "user1", onJoinRoom: { _ in })
    }
}

import Foundation

struct RecentRoom: Identifiable, Codable {
    var id: String { code }
    let code: String
    let lastPlayedAt: Date
}

enum RecentRooms {
    static let storageKey = "recentRooms"
    private static let maxCount = 10

    static func decode(from data: Data) -> [RecentRoom] {
        (try? JSONDecoder().decode([RecentRoom].self, from: data)) ?? []
    }

    static func encode(_ rooms: [RecentRoom]) -> Data {
        (try? JSONEncoder().encode(rooms)) ?? Data()
    }

    static func recordPlay(code: String, in data: Data) -> Data {
        var rooms = decode(from: data).filter { $0.code != code }
        rooms.insert(RecentRoom(code: code, lastPlayedAt: Date()), at: 0)
        if rooms.count > maxCount { rooms = Array(rooms.prefix(maxCount)) }
        return encode(rooms)
    }
}

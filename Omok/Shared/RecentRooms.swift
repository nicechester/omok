import Foundation

struct RecentRoom: Identifiable, Codable {
    var id: String { code }
    let code: String
    let lastPlayedAt: Date
    let aiDifficulty: AIDifficulty?
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

    static func recordPlay(code: String, aiDifficulty: AIDifficulty? = nil, in data: Data) -> Data {
        var rooms = decode(from: data).filter { $0.code != code }
        rooms.insert(RecentRoom(code: code, lastPlayedAt: Date(), aiDifficulty: aiDifficulty), at: 0)
        if rooms.count > maxCount { rooms = Array(rooms.prefix(maxCount)) }
        return encode(rooms)
    }

    static func remove(code: String, from data: Data) -> Data {
        let rooms = decode(from: data).filter { $0.code != code }
        return encode(rooms)
    }

    static func restore(_ room: RecentRoom, at index: Int, in data: Data) -> Data {
        var rooms = decode(from: data)
        let clamped = min(max(index, 0), rooms.count)
        rooms.insert(room, at: clamped)
        return encode(rooms)
    }
}

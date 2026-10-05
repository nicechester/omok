import Foundation

enum RecentEmojis {
    static let storageKey = "recentEmojis"
    private static let maxCount = 5
    private static let defaultEmojis = ["1F604", "1F62E", "1F44F", "1F914", "1F605"]

    static func get(from data: Data) -> [String] {
        let stored = (try? JSONDecoder().decode([String].self, from: data)) ?? []
        guard !stored.isEmpty else { return defaultEmojis }
        return stored
    }

    static func record(_ hexcode: String, in data: Data) -> Data {
        var emojis = (try? JSONDecoder().decode([String].self, from: data)) ?? defaultEmojis
        emojis.removeAll { $0 == hexcode }
        emojis.insert(hexcode, at: 0)
        if emojis.count > maxCount { emojis = Array(emojis.prefix(maxCount)) }
        return (try? JSONEncoder().encode(emojis)) ?? data
    }
}

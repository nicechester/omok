import Foundation

struct Cell: Hashable, Codable, Sendable {
    let r: Int
    let c: Int

    var key: String {
        "\(r)_\(c)"
    }

    init(r: Int, c: Int) {
        self.r = r
        self.c = c
    }

    init?(key: String) {
        let parts = key.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2,
              let r = Int(parts[0]),
              let c = Int(parts[1]) else {
            return nil
        }
        self.r = r
        self.c = c
    }
}

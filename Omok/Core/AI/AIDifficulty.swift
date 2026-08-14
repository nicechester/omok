import Foundation

enum AIDifficulty: Codable, Sendable, Equatable, Hashable {
    case easy
    case normal
    case hard

    var displayName: String {
        switch self {
        case .easy: return "Easy"
        case .normal: return "Normal"
        case .hard: return "Hard"
        }
    }

    var maxDepth: Int {
        switch self {
        case .easy:
            return 2
        case .normal:
            return 4
        case .hard:
            return 6
        }
    }

    var timeLimit: TimeInterval {
        switch self {
        case .easy:
            return 0.5
        case .normal:
            return 2.0
        case .hard:
            return 5.0
        }
    }
}

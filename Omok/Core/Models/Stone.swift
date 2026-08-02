import Foundation

enum Stone: String, Codable, Sendable {
    case black
    case white

    var opposite: Stone {
        switch self {
        case .black:
            return .white
        case .white:
            return .black
        }
    }
}

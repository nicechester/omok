import Foundation

/// Pure nickname sanitization rules. No Firebase dependency, mirroring
/// `Shared/GomokuRules.swift` as a static-only namespace.
enum PlayerName {
    static let storageKey = "playerName"
    static let maxLength = 20

    static func sanitize(_ raw: String) -> String {
        var trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.utf16.count > maxLength {
            trimmed.removeLast()
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func isValid(_ raw: String) -> Bool {
        !sanitize(raw).isEmpty
    }
}

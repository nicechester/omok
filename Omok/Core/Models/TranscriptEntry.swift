import Foundation

struct TranscriptEntry: Identifiable, Equatable {
    let id: UUID
    let speaker: Stone?      // nil = unattributable (spectator, multi-speaker)
    var text: String
    var isFinal: Bool
    let startedAt: Date
    var updatedAt: Date
}

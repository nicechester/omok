import SwiftUI

struct TranscriptBannerView: View {
    let transcripts: [TranscriptEntry]
    let mySeat: Stone?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(transcripts.suffix(3)) { entry in
                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.speaker == .black ? Color.black :
                              entry.speaker == .white ? Color.white : Color.gray)
                        .frame(width: 8, height: 8)
                        .overlay(Circle().stroke(Color.gray, lineWidth: 0.5))

                    Text(entry.text)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.tail)

                    Spacer()
                }
                .opacity(entry.isFinal ? 0.7 : 1.0)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemGray6).opacity(0.9))
        .cornerRadius(6)
    }
}

#Preview {
    VStack {
        TranscriptBannerView(
            transcripts: [
                TranscriptEntry(
                    id: UUID(),
                    speaker: .black,
                    text: "Hello there!",
                    isFinal: false,
                    startedAt: Date(),
                    updatedAt: Date()
                ),
                TranscriptEntry(
                    id: UUID(),
                    speaker: .white,
                    text: "Hi! How are you?",
                    isFinal: true,
                    startedAt: Date(),
                    updatedAt: Date()
                ),
            ],
            mySeat: .black
        )
        .padding()

        Spacer()
    }
}

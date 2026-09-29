import SwiftUI

struct EmojiPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 6)

    private static let emojiData: [(hexcode: String, tags: String)] = {
        guard let url = Bundle.main.url(forResource: "openmoji", withExtension: "csv"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        var result: [(String, String)] = []
        let lines = content.components(separatedBy: .newlines).dropFirst()
        for line in lines {
            let cols = parseCSVLine(line)
            guard cols.count >= 7 else { continue }
            let hexcode = cols[1]
            // Skip skin tone variants and long codes
            if hexcode.contains("-") && hexcode.count > 10 { continue }
            let annotation = cols[4].lowercased()
            let tags = cols[5].lowercased()
            let openmojiTags = cols[6].lowercased()
            result.append((hexcode, "\(annotation) \(tags) \(openmojiTags)"))
        }
        return result
    }()

    private static func parseCSVLine(_ line: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" { inQuotes.toggle() }
            else if char == "," && !inQuotes { result.append(current); current = "" }
            else { current.append(char) }
        }
        result.append(current)
        return result
    }

    private var filteredEmoji: [(hexcode: String, tags: String)] {
        guard !searchText.isEmpty else { return Self.emojiData }
        let query = searchText.lowercased()
        return Self.emojiData.filter { $0.tags.contains(query) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(filteredEmoji, id: \.hexcode) { emoji in
                        Button {
                            onSelect(emoji.hexcode)
                            dismiss()
                        } label: {
                            OpenMojiImage(hexcode: emoji.hexcode)
                                .frame(width: 48, height: 48)
                        }
                    }
                }
                .padding()
            }
            .searchable(text: $searchText, prompt: "Search emoji")
            .navigationTitle("Emoji")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct OpenMojiImage: View {
    let hexcode: String

    var body: some View {
        if let path = Bundle.main.path(forResource: hexcode, ofType: "png", inDirectory: "OpenMoji"),
           let uiImage = UIImage(contentsOfFile: path) {
            Image(uiImage: uiImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            Color.clear
        }
    }
}

#Preview {
    EmojiPickerSheet { hexcode in
        print("Selected: \(hexcode)")
    }
}

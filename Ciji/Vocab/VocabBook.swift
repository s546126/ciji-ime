import Foundation

/// 生词本: words starred from the candidate panel (Ctrl+S), reviewed with a
/// simple spaced-repetition schedule. A due word is flagged 「复习」 in the panel;
/// typing and committing it counts as a review and pushes the next due date out.
/// Stored in ~/Library/Application Support/Ciji/vocab.json.
final class VocabBook {
    static let shared = VocabBook()

    struct Item: Codable {
        var phrase: String
        var pinyin: String
        var gloss: String
        var added: Date
        var stage: Int
        var due: Date
        var reviews: Int
    }

    /// Days until the next review after each successful review.
    static let intervals = [1, 2, 4, 7, 15, 30, 60, 120]

    private(set) var items: [String: Item] = [:]

    private init() {
        if let data = try? Data(contentsOf: Self.url()) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let list = try? decoder.decode([Item].self, from: data) {
                items = Dictionary(list.map { ($0.phrase, $0) }, uniquingKeysWith: { a, _ in a })
            }
        }
    }

    static func url() -> URL {
        AppConfig.supportDirectory().appendingPathComponent("vocab.json")
    }

    static func csvURL() -> URL {
        AppConfig.supportDirectory().appendingPathComponent("生词本.csv")
    }

    func contains(_ phrase: String) -> Bool {
        items[phrase] != nil
    }

    func isDue(_ phrase: String, now: Date = Date()) -> Bool {
        guard let item = items[phrase] else { return false }
        return item.due <= now
    }

    var dueItems: [Item] {
        let now = Date()
        return items.values.filter { $0.due <= now }.sorted { $0.due < $1.due }
    }

    /// Adds or removes the candidate; returns true when it is now in the book.
    @discardableResult
    func toggle(_ candidate: Candidate) -> Bool {
        if items.removeValue(forKey: candidate.phrase) != nil {
            save()
            return false
        }
        let now = Date()
        items[candidate.phrase] = Item(
            phrase: candidate.phrase,
            pinyin: candidate.syllables.joined(separator: " "),
            gloss: candidate.gloss,
            added: now,
            stage: 0,
            due: now.addingTimeInterval(Double(Self.intervals[0]) * 86_400),
            reviews: 0
        )
        save()
        return true
    }

    /// Called for every committed phrase; advances due words.
    func committed(_ phrase: String) {
        guard var item = items[phrase], item.due <= Date() else { return }
        item.reviews += 1
        item.stage = min(item.stage + 1, Self.intervals.count - 1)
        item.due = Date().addingTimeInterval(Double(Self.intervals[item.stage]) * 86_400)
        items[phrase] = item
        save()
    }

    private func save() {
        let list = items.values.sorted { $0.added < $1.added }
        DispatchQueue.global(qos: .utility).async {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try? FileManager.default.createDirectory(at: AppConfig.supportDirectory(), withIntermediateDirectories: true)
            if let data = try? encoder.encode(list) {
                try? data.write(to: Self.url(), options: .atomic)
            }
        }
    }

    /// Writes an Anki-importable CSV (中文, 拼音, English, 下次复习) and returns its URL.
    func exportCSV() -> URL {
        func field(_ s: String) -> String {
            "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        var lines = ["中文,拼音,English,下次复习,复习次数"]
        for item in items.values.sorted(by: { $0.due < $1.due }) {
            lines.append([
                field(item.phrase), field(item.pinyin), field(item.gloss),
                field(formatter.string(from: item.due)), String(item.reviews),
            ].joined(separator: ","))
        }
        let url = Self.csvURL()
        try? FileManager.default.createDirectory(at: AppConfig.supportDirectory(), withIntermediateDirectories: true)
        // BOM so Excel/Numbers open the UTF-8 CSV correctly.
        try? ("\u{FEFF}" + lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}

import Foundation

/// Learns from what the user commits:
/// * per-phrase counts → the phrase ranks higher next time;
/// * composed sentences → become words of their own;
/// * previous-word → next-word pairs → context-aware ranking
///   (after 汽车, `youxiang` prefers 油箱 once you have typed it that way).
/// Stored in ~/Library/Application Support/Ciji/history.json.
final class UserHistory {
    static let shared = UserHistory()

    private struct Store: Codable {
        var counts: [String: Int] = [:]
        var phrases: [String: [String]] = [:] // phrase -> syllables
        var bigrams: [String: [String: Int]] = [:] // previous -> next -> count
    }

    private var store = Store()
    private var saveScheduled = false
    /// Last committed phrase, used as context for the next lookup.
    private(set) var previous: String?

    private init() {
        if let data = try? Data(contentsOf: Self.url()),
           let decoded = try? JSONDecoder().decode(Store.self, from: data) {
            store = decoded
        }
    }

    static func url() -> URL {
        AppConfig.supportDirectory().appendingPathComponent("history.json")
    }

    static func boost(forCount count: Int) -> Double {
        count > 0 ? 1.2 * log(1 + Double(count)) : 0
    }

    func apply(to lexicon: Lexicon) {
        for (phrase, syllables) in store.phrases {
            lexicon.addUserPhrase(phrase, syllables: syllables, gloss: "")
        }
        for (phrase, count) in store.counts {
            lexicon.setBoost(Self.boost(forCount: count), for: phrase)
        }
    }

    /// Extra score for `phrase` given the previously committed phrase.
    func contextBonus(for phrase: String) -> Double {
        guard let prev = previous, let count = store.bigrams[prev]?[phrase], count > 0 else { return 0 }
        return 1.5 + log(Double(count))
    }

    func resetContext() {
        previous = nil
    }

    func record(_ candidate: Candidate, lexicon: Lexicon = .shared) {
        let phrase = candidate.phrase
        guard !phrase.isEmpty else { return }
        let count = (store.counts[phrase] ?? 0) + 1
        store.counts[phrase] = count
        if candidate.source == "sentence", candidate.syllables.count == phrase.count, phrase.count <= 8 {
            store.phrases[phrase] = candidate.syllables
            lexicon.addUserPhrase(phrase, syllables: candidate.syllables, gloss: candidate.gloss)
        }
        lexicon.setBoost(Self.boost(forCount: count), for: phrase)
        if let prev = previous {
            store.bigrams[prev, default: [:]][phrase, default: 0] += 1
        }
        previous = phrase
        trim()
        scheduleSave()
    }

    private func trim() {
        if store.counts.count > 20_000 {
            let keep = store.counts.sorted { $0.value > $1.value }.prefix(15_000)
            store.counts = Dictionary(uniqueKeysWithValues: keep.map { ($0.key, $0.value) })
        }
        if store.bigrams.count > 20_000 {
            store.bigrams = store.bigrams.filter { store.counts[$0.key] != nil }
        }
    }

    private func scheduleSave() {
        guard !saveScheduled else { return }
        saveScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in
            self?.save()
        }
    }

    func save() {
        saveScheduled = false
        let snapshot = store
        DispatchQueue.global(qos: .utility).async {
            let dir = AppConfig.supportDirectory()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.url(), options: .atomic)
            }
        }
    }
}

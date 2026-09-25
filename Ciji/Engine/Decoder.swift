import Foundation

/// Mirrors `Candidate` in scripts/ciji_engine.py.
struct Candidate: Equatable {
    var phrase: String
    var gloss: String
    /// Number of typed keys this candidate replaces.
    var consumed: Int
    var segmented: String
    var score: Double
    var source: String // "sentence" | "word" | "partial"
    /// Pinyin of the phrase; lets UserHistory learn composed sentences.
    var syllables: [String]
}

struct Segmentation {
    var units: [String]
    var ends: [Int]
    var rest: String
    var display: String

    static func make(_ scheme: Scheme, keys raw: String) -> Segmentation {
        let keys = raw.lowercased()
        switch scheme {
        case .xiaohe:
            let (units, rest) = Xiaohe.chunk(keys)
            let ends = units.indices.map { 2 * ($0 + 1) }
            return Segmentation(units: units, ends: ends, rest: rest, display: Pinyin.formatSegmented(units, rest: rest))
        case .quanpin:
            var units: [String] = []
            var ends: [Int] = []
            var offset = 0
            var rest = ""
            let chunks = keys.split(separator: "'", omittingEmptySubsequences: false).map(String.init)
            for (idx, chunk) in chunks.enumerated() {
                let (head, tail) = Pinyin.segmentQuanpinPrefix(chunk)
                for syl in head {
                    offset += syl.count
                    units.append(syl)
                    ends.append(offset)
                }
                if !tail.isEmpty {
                    rest = idx == chunks.count - 1 ? tail : ([tail] + chunks[(idx + 1)...]).joined(separator: "'")
                    break
                }
                offset += 1 // apostrophe
            }
            return Segmentation(units: units, ends: ends, rest: rest, display: Pinyin.formatSegmented(units, rest: rest))
        }
    }
}

enum InputDecoder {
    /// Completing the last syllable (quanpin "zhonggu" → 中国) costs this much log-prob.
    static let extensionPenalty = 2.5

    static func decode(
        keys: String,
        scheme: Scheme,
        lexicon: Lexicon = .shared,
        context: (String) -> Double = { UserHistory.shared.contextBonus(for: $0) }
    ) -> [Candidate] {
        let keys = keys.lowercased()
        guard !keys.isEmpty else { return [] }
        let seg = Segmentation.make(scheme, keys: keys)
        let units = seg.units
        let rest = seg.rest
        let n = units.count
        let totalKeys = keys.count

        func exact(_ i: Int, _ j: Int) -> [LexEntry] {
            let words = lexicon.exact(scheme, units[i..<j].joined())
            if scheme == .quanpin {
                let want = Array(units[i..<j])
                return words.filter { $0.syllables == want }
            }
            return words
        }

        func bestOf(_ words: [LexEntry]) -> LexEntry? {
            // Lists are frequency-sorted; learned boosts can reorder the head.
            words.prefix(6).max { lexicon.logp($0) < lexicon.logp($1) }
        }

        // Sentence DP over complete units, plus an optional partial last word.
        let neg = -Double.infinity
        var best = [Double](repeating: neg, count: n + 2)
        var path = [[LexEntry]](repeating: [], count: n + 2)
        best[0] = 0
        if n > 0 {
            for end in 1...n {
                for start in 0..<end where best[start] > neg {
                    guard let w = bestOf(exact(start, end)) else { continue }
                    let sc = best[start] + lexicon.logp(w) + (start == 0 ? context(w.phrase) : 0)
                    if sc > best[end] {
                        best[end] = sc
                        path[end] = path[start] + [w]
                    }
                }
            }
        }
        var final = n
        if !rest.isEmpty {
            for start in 0...n where best[start] > neg {
                guard let w = lexicon.completions(scheme, head: Array(units[start..<n]), tail: rest, limit: 1).first else {
                    continue
                }
                let sc = best[start] + lexicon.logp(w)
                if sc > best[n + 1] {
                    best[n + 1] = sc
                    path[n + 1] = path[start] + [w]
                }
            }
            final = n + 1
        }

        var out: [Candidate] = []
        var seen = Set<String>()
        func add(_ phrase: String, _ gloss: String, _ consumed: Int, _ score: Double, _ source: String, _ syllables: [String]) {
            guard !phrase.isEmpty, !seen.contains(phrase) else { return }
            seen.insert(phrase)
            out.append(Candidate(
                phrase: phrase, gloss: gloss, consumed: consumed, segmented: seg.display,
                score: score, source: source, syllables: syllables
            ))
        }

        // Words covering the whole input.
        var full: [(Double, LexEntry)] = []
        if n > 0 && rest.isEmpty {
            full += exact(0, n).map { (lexicon.logp($0) + context($0.phrase), $0) }
            if scheme == .quanpin && n >= 2 {
                for e in lexicon.completions(scheme, head: Array(units[0..<(n - 1)]), tail: units[n - 1], limit: 12)
                where e.syllables.last != units[n - 1] {
                    full.append((lexicon.logp(e) + context(e.phrase) - extensionPenalty, e))
                }
            }
        } else if !rest.isEmpty {
            full += lexicon.completions(scheme, head: units, tail: rest, limit: 40).map { (lexicon.logp($0) + context($0.phrase), $0) }
        }
        full.sort { $0.0 > $1.0 }

        var sentence = best[final] > neg ? path[final] : []
        let sentenceScore = best[final]
        func addSentence() {
            add(
                sentence.map(\.phrase).joined(),
                sentenceGloss(sentence),
                totalKeys,
                sentenceScore,
                "sentence",
                sentence.flatMap(\.syllables)
            )
        }
        if sentence.count >= 2, full.isEmpty || sentenceScore > full[0].0 {
            addSentence()
            sentence = []
        }
        for (i, item) in full.enumerated() {
            add(item.1.phrase, item.1.gloss, totalKeys, item.0, "word", item.1.syllables)
            if i == 0 && sentence.count >= 2 {
                addSentence()
            }
        }

        // Words covering a prefix of the input, longest first.
        let top = rest.isEmpty ? n - 1 : n
        if top >= 1 {
            for k in stride(from: top, through: 1, by: -1) {
                var words = exact(0, k)
                if k >= 2 { words = Array(words.prefix(6)) }
                if !words.isEmpty {
                    words.sort { lexicon.logp($0) + context($0.phrase) > lexicon.logp($1) + context($1.phrase) }
                }
                for e in words {
                    add(e.phrase, e.gloss, seg.ends[k - 1], lexicon.logp(e), "partial", e.syllables)
                }
            }
        }

        if n == 0 && !rest.isEmpty {
            for e in lexicon.completions(scheme, head: [], tail: rest, limit: 60) {
                add(e.phrase, e.gloss, totalKeys, lexicon.logp(e), "word", e.syllables)
            }
        }
        return out
    }

    static func sentenceGloss(_ words: [LexEntry]) -> String {
        words.compactMap { e -> String? in
            var g = String(e.gloss.split(separator: ";").first ?? "").trimmingCharacters(in: .whitespaces)
            if g.hasPrefix("≈ ") { g.removeFirst(2) }
            return g.isEmpty ? nil : g
        }.joined(separator: " · ")
    }
}

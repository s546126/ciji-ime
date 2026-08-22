import Foundation

struct Candidate: Equatable {
    var phrase: String
    var gloss: String
    var consumed: Int
    var segmented: String
    var score: Int
    var source: String
}

enum InputDecoder {
    static func decode(keys: String, scheme: Scheme, lexicon: Lexicon = .shared) -> [Candidate] {
        let lowered = keys.lowercased()
        guard !lowered.isEmpty else { return [] }
        switch scheme {
        case .xiaohe:
            let (units, rest) = Xiaohe.chunk(lowered)
            return decodeUnits(
                units: units,
                rest: rest,
                rawKeys: lowered,
                lexicon: lexicon,
                exact: { lexicon.exactXiaohe($0) },
                prefix: { lexicon.prefixXiaohe($0) }
            )
        case .quanpin:
            let (units, rest) = Pinyin.segmentQuanpinPrefix(lowered)
            return decodeUnits(
                units: units,
                rest: rest,
                rawKeys: lowered,
                lexicon: lexicon,
                exact: { lexicon.exactQuanpin($0) },
                prefix: { lexicon.prefixQuanpin($0) }
            )
        }
    }

    private static func decodeUnits(
        units: [String],
        rest: String,
        rawKeys: String,
        lexicon: Lexicon,
        exact: (String) -> [LexEntry],
        prefix: (String) -> [LexEntry]
    ) -> [Candidate] {
        let n = units.count
        var bestScore = [Int](repeating: Int.min / 4, count: n + 1)
        var bestPath = [[LexEntry]?](repeating: nil, count: n + 1)
        bestScore[0] = 0
        bestPath[0] = []

        if n > 0 {
            for end in 1...n {
                for start in 0..<end {
                    guard bestPath[start] != nil else { continue }
                    let code = units[start..<end].joined()
                    for entry in exact(code) {
                        let sc = bestScore[start] + dpWeight(entry)
                        if sc > bestScore[end] {
                            bestScore[end] = sc
                            bestPath[end] = (bestPath[start] ?? []) + [entry]
                        }
                    }
                }
            }
        }

        var candidates: [Candidate] = []
        var seen = Set<String>()
        let segmented = Pinyin.formatSegmented(units, rest: rest)
        let fullConsumed = rawKeys.count - rest.count

        func add(_ phrase: String, _ gloss: String, _ consumed: Int, _ score: Int, _ source: String) {
            guard !phrase.isEmpty, !seen.contains(phrase) else { return }
            seen.insert(phrase)
            candidates.append(
                Candidate(
                    phrase: phrase,
                    gloss: gloss,
                    consumed: consumed,
                    segmented: segmented,
                    score: score,
                    source: source
                )
            )
        }

        if n > 0, let path = bestPath[n], !path.isEmpty {
            let phrase = path.map(\.phrase).joined()
            var gloss = path.map(\.gloss).filter { !$0.isEmpty }.joined(separator: " / ")
            let fullCode = units.joined()
            if let match = exact(fullCode).first(where: { $0.phrase == phrase && !$0.gloss.isEmpty }) {
                gloss = match.gloss
            }
            add(phrase, gloss, fullConsumed, bestScore[n] + 5000, "sentence")
        }

        if n > 0 {
            for end in stride(from: n, through: 1, by: -1) {
                let code = units[0..<end].joined()
                let consumedKeys = units[0..<end].joined().count
                for entry in exact(code) {
                    add(
                        entry.phrase,
                        entry.gloss,
                        consumedKeys,
                        entryScore(entry, consumed: consumedKeys, inputLen: rawKeys.count) + end * 80,
                        "phrase"
                    )
                }
            }
        }

        if !rest.isEmpty {
            let code = units.joined() + rest
            for entry in prefix(code) {
                add(
                    entry.phrase,
                    entry.gloss,
                    rawKeys.count,
                    entryScore(entry, consumed: rawKeys.count, inputLen: rawKeys.count),
                    "phrase"
                )
            }
        }

        if n >= 1 {
            let code = units[0]
            for entry in exact(code) {
                add(
                    entry.phrase,
                    entry.gloss,
                    units[0].count,
                    entryScore(entry, consumed: units[0].count, inputLen: rawKeys.count),
                    "phrase"
                )
            }
        } else if !rest.isEmpty {
            for entry in prefix(rest) {
                add(
                    entry.phrase,
                    entry.gloss,
                    rawKeys.count,
                    entryScore(entry, consumed: rawKeys.count, inputLen: rawKeys.count),
                    "phrase"
                )
            }
        }

        if n >= 2 {
            let firstChars = exact(units[0]).filter { usableChar($0) }.sorted { $0.freq > $1.freq }
            let secondChars = exact(units[1]).filter { usableChar($0) }.sorted { $0.freq > $1.freq }
            let consumedTwo = units[0].count + units[1].count
            for a in firstChars.prefix(8) {
                for b in secondChars.prefix(4) {
                    let combo = a.phrase + b.phrase
                    var gloss = a.gloss.isEmpty ? b.gloss : a.gloss
                    if !a.gloss.isEmpty, !b.gloss.isEmpty, a.gloss != b.gloss {
                        gloss = "\(a.gloss); \(b.gloss)"
                    }
                    add(combo, Pinyin.shortenGloss(gloss), consumedTwo, min(a.freq, b.freq) / 4 + 80, "compose")
                }
            }
        }

        candidates.sort {
            if $0.score != $1.score { return $0.score > $1.score }
            if $0.phrase.count != $1.phrase.count { return $0.phrase.count < $1.phrase.count }
            return $0.phrase < $1.phrase
        }
        return candidates
    }

    private static func usableChar(_ entry: LexEntry) -> Bool {
        guard entry.phrase.count == 1 else { return false }
        let low = entry.gloss.lowercased()
        return !low.contains("variant of") && !low.contains("archaic")
    }

    private static func entryScore(_ entry: LexEntry, consumed: Int, inputLen: Int) -> Int {
        var score = entry.freq
        if consumed == inputLen && entry.xiaohe.count == inputLen {
            score += 8000
        } else if consumed == inputLen {
            score += 3500
        }
        score += consumed * 40
        score += min(entry.syllableCount, 4) * 25
        if entry.syllableCount == 1 {
            score -= 15
        }
        return score
    }

    private static func dpWeight(_ entry: LexEntry) -> Int {
        if entry.syllableCount >= 2 {
            return 3000 * entry.syllableCount + min(entry.freq, 12_000)
        }
        return entry.freq >= 1000 ? 400 : 80
    }
}

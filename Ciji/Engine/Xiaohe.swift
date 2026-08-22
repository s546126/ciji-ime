import Foundation

enum Scheme: String {
    case xiaohe
    case quanpin

    var displayName: String {
        switch self {
        case .xiaohe: return "小鹤双拼"
        case .quanpin: return "全拼"
        }
    }
}

enum Xiaohe {
    static let initialKeys: [String: Character] = [
        "b": "b", "p": "p", "m": "m", "f": "f",
        "d": "d", "t": "t", "n": "n", "l": "l",
        "g": "g", "k": "k", "h": "h",
        "j": "j", "q": "q", "x": "x",
        "r": "r", "z": "z", "c": "c", "s": "s",
        "y": "y", "w": "w",
        "zh": "v", "ch": "i", "sh": "u",
    ]

    static let finalKeys: [String: Character] = [
        "a": "a", "o": "o", "e": "e", "i": "i", "u": "u", "v": "v",
        "ai": "d", "ei": "w", "ui": "v",
        "ao": "c", "ou": "z", "iu": "q", "ie": "p",
        "ue": "t", "ve": "t",
        "an": "j", "en": "f", "in": "b", "un": "y", "vn": "y",
        "ang": "h", "eng": "g", "ing": "k",
        "ong": "s", "iong": "s",
        "ia": "x", "ua": "x",
        "iao": "n", "ian": "m",
        "iang": "l", "uang": "l",
        "uai": "k", "uan": "r", "uo": "o",
    ]

    static func encodeSyllable(_ syllable: String) -> String? {
        let s = Pinyin.normalizeSyllable(syllable)
        guard Pinyin.validSyllables.contains(s) else { return nil }
        let (initial, final) = Pinyin.splitInitialFinal(s)
        if initial.isEmpty {
            if final.count == 1 {
                return final + final
            }
            if final.count == 2 {
                return final
            }
            guard let key = finalKeys[final] else { return nil }
            return String(final.prefix(1)) + String(key)
        }
        guard let initKey = initialKeys[initial], let finKey = finalKeys[final] else {
            return nil
        }
        return String(initKey) + String(finKey)
    }

    static func encode(_ syllables: [String]) -> String? {
        var out = ""
        for syl in syllables {
            guard let code = encodeSyllable(syl) else { return nil }
            out += code
        }
        return out
    }

    static func chunk(_ keys: String) -> (complete: [String], rest: String) {
        let s = keys.lowercased()
        var complete: [String] = []
        var idx = s.startIndex
        while s.distance(from: idx, to: s.endIndex) >= 2 {
            let mid = s.index(idx, offsetBy: 2)
            complete.append(String(s[idx..<mid]))
            idx = mid
        }
        return (complete, String(s[idx...]))
    }
}

import Foundation

enum Pinyin {
    static let zeroInitials: Set<String> = [
        "a", "ai", "an", "ang", "ao",
        "e", "ei", "en", "eng", "er",
        "o", "ou",
    ]

    static let validSyllables: Set<String> = [
        "a", "ai", "an", "ang", "ao", "e", "ei", "en", "eng", "er", "o", "ou",
        "ba", "bai", "ban", "bang", "bao", "bei", "ben", "beng", "bi", "bian", "biao", "bie", "bin", "bing", "bo", "bu",
        "ca", "cai", "can", "cang", "cao", "ce", "cen", "ceng", "ci", "cong", "cou", "cu", "cuan", "cui", "cun", "cuo",
        "cha", "chai", "chan", "chang", "chao", "che", "chen", "cheng", "chi", "chong", "chou", "chu", "chua", "chuai",
        "chuan", "chuang", "chui", "chun", "chuo",
        "da", "dai", "dan", "dang", "dao", "de", "dei", "den", "deng", "di", "dia", "dian", "diao", "die", "ding", "diu",
        "dong", "dou", "du", "duan", "dui", "dun", "duo",
        "fa", "fan", "fang", "fei", "fen", "feng", "fo", "fou", "fu",
        "ga", "gai", "gan", "gang", "gao", "ge", "gei", "gen", "geng", "gong", "gou", "gu", "gua", "guai", "guan",
        "guang", "gui", "gun", "guo",
        "ha", "hai", "han", "hang", "hao", "he", "hei", "hen", "heng", "hong", "hou", "hu", "hua", "huai", "huan",
        "huang", "hui", "hun", "huo",
        "ji", "jia", "jian", "jiang", "jiao", "jie", "jin", "jing", "jiong", "jiu", "ju", "juan", "jue", "jun",
        "ka", "kai", "kan", "kang", "kao", "ke", "ken", "keng", "kong", "kou", "ku", "kua", "kuai", "kuan", "kuang",
        "kui", "kun", "kuo",
        "la", "lai", "lan", "lang", "lao", "le", "lei", "leng", "li", "lia", "lian", "liang", "liao", "lie", "lin",
        "ling", "liu", "lo", "long", "lou", "lu", "luan", "lue", "lun", "luo", "lv", "lve",
        "ma", "mai", "man", "mang", "mao", "me", "mei", "men", "meng", "mi", "mian", "miao", "mie", "min", "ming",
        "miu", "mo", "mou", "mu",
        "na", "nai", "nan", "nang", "nao", "ne", "nei", "nen", "neng", "ni", "nian", "niang", "niao", "nie", "nin",
        "ning", "niu", "nong", "nou", "nu", "nuan", "nue", "nuo", "nv", "nve",
        "pa", "pai", "pan", "pang", "pao", "pei", "pen", "peng", "pi", "pian", "piao", "pie", "pin", "ping", "po",
        "pou", "pu",
        "qi", "qia", "qian", "qiang", "qiao", "qie", "qin", "qing", "qiong", "qiu", "qu", "quan", "que", "qun",
        "ran", "rang", "rao", "re", "ren", "reng", "ri", "rong", "rou", "ru", "rua", "ruan", "rui", "run", "ruo",
        "sa", "sai", "san", "sang", "sao", "se", "sen", "seng", "si", "song", "sou", "su", "suan", "sui", "sun", "suo",
        "sha", "shai", "shan", "shang", "shao", "she", "shei", "shen", "sheng", "shi", "shou", "shu", "shua", "shuai",
        "shuan", "shuang", "shui", "shun", "shuo",
        "ta", "tai", "tan", "tang", "tao", "te", "tei", "teng", "ti", "tian", "tiao", "tie", "ting", "tong", "tou",
        "tu", "tuan", "tui", "tun", "tuo",
        "wa", "wai", "wan", "wang", "wei", "wen", "weng", "wo", "wu",
        "xi", "xia", "xian", "xiang", "xiao", "xie", "xin", "xing", "xiong", "xiu", "xu", "xuan", "xue", "xun",
        "ya", "yan", "yang", "yao", "ye", "yi", "yin", "ying", "yo", "yong", "you", "yu", "yuan", "yue", "yun",
        "za", "zai", "zan", "zang", "zao", "ze", "zei", "zen", "zeng", "zi", "zong", "zou", "zu", "zuan", "zui",
        "zun", "zuo",
        "zha", "zhai", "zhan", "zhang", "zhao", "zhe", "zhei", "zhen", "zheng", "zhi", "zhong", "zhou", "zhu", "zhua",
        "zhuai", "zhuan", "zhuang", "zhui", "zhun", "zhuo",
    ]

    static let maxSyllableLength = 6

    static func normalizeSyllable(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        while let last = s.last, "12345".contains(last) {
            s.removeLast()
        }
        s = s.replacingOccurrences(of: "u:", with: "v")
            .replacingOccurrences(of: "ü", with: "v")
            .replacingOccurrences(of: "ê", with: "e")
        if s == "lue" || s == "nue" {
            s = String(s.prefix(1)) + "ve"
        }
        return s
    }

    static func splitInitialFinal(_ syllable: String) -> (String, String) {
        let s = normalizeSyllable(syllable)
        if s.hasPrefix("zh") || s.hasPrefix("ch") || s.hasPrefix("sh") {
            if s.count >= 3 {
                let idx = s.index(s.startIndex, offsetBy: 2)
                return (String(s[..<idx]), String(s[idx...]))
            }
        }
        if zeroInitials.contains(s) {
            return ("", s)
        }
        if let first = s.first, "bpmfdtnlgkhjqxrzcsyw".contains(first), s.count > 1 {
            return (String(first), String(s.dropFirst()))
        }
        return ("", s)
    }

    static func segmentQuanpin(_ keys: String) -> [String]? {
        let s = Array(keys.lowercased())
        let n = s.count
        if n == 0 { return [] }
        var prev = [Int?](repeating: nil, count: n + 1)
        prev[0] = -1
        if n > 0 {
            for i in 0..<n where prev[i] != nil {
                let maxLen = min(maxSyllableLength, n - i)
                if maxLen >= 1 {
                    for length in 1...maxLen {
                        let piece = String(s[i..<(i + length)])
                        if validSyllables.contains(piece), prev[i + length] == nil {
                            prev[i + length] = i
                        }
                    }
                }
            }
        }
        guard prev[n] != nil else { return nil }
        var out: [String] = []
        var i = n
        while i > 0 {
            guard let j = prev[i], j >= 0 else { return nil }
            out.append(String(s[j..<i]))
            i = j
        }
        return out.reversed()
    }

    static func segmentQuanpinPrefix(_ keys: String) -> (complete: [String], rest: String) {
        let s = keys.lowercased()
        if s.isEmpty { return ([], "") }
        if let full = segmentQuanpin(s) {
            return (full, "")
        }
        if s.count > 1 {
            for cut in stride(from: s.count - 1, through: 1, by: -1) {
                let idx = s.index(s.startIndex, offsetBy: cut)
                if let head = segmentQuanpin(String(s[..<idx])) {
                    return (head, String(s[idx...]))
                }
            }
        }
        return ([], s)
    }

    static func formatSegmented(_ parts: [String], rest: String) -> String {
        var bits = parts
        if !rest.isEmpty { bits.append(rest) }
        return bits.joined(separator: "'")
    }

    static func shortenGloss(_ gloss: String, limit: Int = 28) -> String {
        let parts = gloss.split(separator: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var cleaned: [String] = []
        for part in (parts.isEmpty ? [gloss] : parts) {
            let low = part.lowercased()
            if low.hasPrefix("see ") || low.contains("variant of") || low.hasPrefix("erhua") || low.hasPrefix("archaic") {
                continue
            }
            cleaned.append(part)
            if cleaned.count >= 2 { break }
        }
        if cleaned.isEmpty, let first = parts.first {
            cleaned = [String(first)]
        }
        var joined = cleaned.joined(separator: "; ")
        if joined.count > limit {
            joined = String(joined.prefix(limit - 1)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return joined
    }
}

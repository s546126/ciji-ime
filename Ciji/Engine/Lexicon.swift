import Foundation
import zlib

/// One dictionary row. Mirrors `LexEntry` in scripts/ciji_engine.py.
struct LexEntry {
    let phrase: String
    /// Space separated tone-less syllables, e.g. "wo de".
    let syllableText: String
    let syllableCount: Int
    let xiaohe: String
    let quanpin: String
    let gloss: String
    let freq: Int

    var syllables: [String] {
        syllableText.split(separator: " ").map(String.init)
    }
}

enum GzipInflate {
    static func decompress(_ data: Data) -> Data? {
        guard data.count > 10, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        var stream = z_stream()
        let status = inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        return data.withUnsafeBytes { raw -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            var output = Data()
            output.reserveCapacity(data.count * 3)
            let chunk = 256 * 1024
            var buffer = [UInt8](repeating: 0, count: chunk)
            var inflateStatus = Z_OK
            repeat {
                let produced = buffer.withUnsafeMutableBufferPointer { dest -> Int in
                    guard let outBase = dest.baseAddress else { return 0 }
                    stream.next_out = outBase
                    stream.avail_out = uInt(dest.count)
                    inflateStatus = inflate(&stream, Z_NO_FLUSH)
                    return dest.count - Int(stream.avail_out)
                }
                if produced > 0 {
                    output.append(contentsOf: buffer[0..<produced])
                }
            } while inflateStatus == Z_OK
            return inflateStatus == Z_STREAM_END ? output : nil
        }
    }
}

final class Lexicon {
    static let shared = Lexicon()

    /// Prefix scans stop after this many distinct codes.
    static let prefixScanLimit = 60_000

    private(set) var entries: [LexEntry] = []
    private var byCode: [Scheme: [String: [Int]]] = [.xiaohe: [:], .quanpin: [:]]
    private var sortedCodes: [Scheme: [String]] = [.xiaohe: [], .quanpin: []]
    private(set) var logTotal: Double = 0
    /// Learned per-phrase bonus (natural-log units) from UserHistory.
    private var boosts: [String: Double] = [:]

    private init() {
        load()
        UserHistory.shared.apply(to: self)
    }

    init(entries: [LexEntry]) {
        index(entries)
    }

    // MARK: lookups

    func logp(_ entry: LexEntry) -> Double {
        log(Double(entry.freq) + 1) - logTotal + (boosts[entry.phrase] ?? 0)
    }

    func exact(_ scheme: Scheme, _ code: String) -> [LexEntry] {
        guard let ids = byCode[scheme]?[code] else { return [] }
        return ids.map { entries[$0] }
    }

    /// Top entries spelled `head` + one more syllable that starts with `tail`.
    func completions(_ scheme: Scheme, head: [String], tail: String, limit: Int) -> [LexEntry] {
        guard let codes = sortedCodes[scheme], let table = byCode[scheme] else { return [] }
        let prefix = head.joined() + tail
        let want = head.count + 1
        var lo = 0
        var hi = codes.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if codes[mid] < prefix { lo = mid + 1 } else { hi = mid }
        }
        var found: [LexEntry] = []
        var i = lo
        var scanned = 0
        while i < codes.count, scanned < Self.prefixScanLimit, codes[i].hasPrefix(prefix) {
            for id in table[codes[i]] ?? [] {
                let e = entries[id]
                guard e.syllableCount == want else { continue }
                if scheme == .quanpin && !Self.quanpinFits(e, head: head, tail: tail) { continue }
                found.append(e)
            }
            i += 1
            scanned += 1
        }
        found.sort { logp($0) > logp($1) }
        return Array(found.prefix(limit))
    }

    private static func quanpinFits(_ e: LexEntry, head: [String], tail: String) -> Bool {
        let syl = e.syllables
        guard syl.count == head.count + 1 else { return false }
        return Array(syl[0..<head.count]) == head && syl[head.count].hasPrefix(tail)
    }

    // MARK: learning

    func setBoost(_ bonus: Double, for phrase: String) {
        boosts[phrase] = bonus
    }

    /// Adds a phrase the user composed (e.g. a sentence) so it becomes a word.
    func addUserPhrase(_ phrase: String, syllables: [String], gloss: String) {
        guard !phrase.isEmpty, syllables.count == phrase.count,
              let xh = Xiaohe.encode(syllables) else { return }
        let qp = syllables.joined()
        if let ids = byCode[.quanpin]?[qp], ids.contains(where: { entries[$0].phrase == phrase }) {
            return
        }
        let entry = LexEntry(
            phrase: phrase,
            syllableText: syllables.joined(separator: " "),
            syllableCount: syllables.count,
            xiaohe: xh,
            quanpin: qp,
            gloss: gloss,
            freq: 1
        )
        entries.append(entry)
        let id = entries.count - 1
        for (scheme, code) in [(Scheme.xiaohe, xh), (Scheme.quanpin, qp)] {
            if byCode[scheme]?[code] == nil {
                var codes = sortedCodes[scheme] ?? []
                var lo = 0
                var hi = codes.count
                while lo < hi {
                    let mid = (lo + hi) / 2
                    if codes[mid] < code { lo = mid + 1 } else { hi = mid }
                }
                codes.insert(code, at: lo)
                sortedCodes[scheme] = codes
            }
            byCode[scheme, default: [:]][code, default: []].append(id)
        }
    }

    // MARK: loading

    private func load() {
        guard let url = Bundle.main.url(forResource: "cedict", withExtension: "tsv.gz")
                ?? Bundle.main.url(forResource: "cedict", withExtension: "tsv.gz", subdirectory: "Resources") else {
            NSLog("Ciji: cedict.tsv.gz not found in bundle")
            return
        }
        let started = Date()
        guard let gz = try? Data(contentsOf: url), let raw = GzipInflate.decompress(gz) else {
            NSLog("Ciji: failed to inflate cedict.tsv.gz")
            return
        }
        let list = Self.parse(raw)
        index(list)
        NSLog("Ciji: loaded \(list.count) lexicon entries in \(Int(Date().timeIntervalSince(started) * 1000)) ms")
    }

    /// Byte-level TSV parser; String.split over 200k lines is noticeably slower.
    static func parse(_ raw: Data) -> [LexEntry] {
        var list: [LexEntry] = []
        list.reserveCapacity(210_000)
        raw.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            let bytes = buf.bindMemory(to: UInt8.self)
            let n = bytes.count
            var lineStart = 0
            while lineStart < n {
                var lineEnd = lineStart
                while lineEnd < n && bytes[lineEnd] != 0x0A { lineEnd += 1 }
                defer { lineStart = lineEnd + 1 }
                if lineEnd == lineStart || bytes[lineStart] == 0x23 { continue } // '#'
                var cols: [String] = []
                cols.reserveCapacity(6)
                var colStart = lineStart
                var i = lineStart
                while i <= lineEnd {
                    if i == lineEnd || bytes[i] == 0x09 {
                        let slice = UnsafeBufferPointer(rebasing: bytes[colStart..<i])
                        cols.append(String(decoding: slice, as: UTF8.self))
                        colStart = i + 1
                    }
                    i += 1
                }
                guard cols.count >= 6, let freq = Int(cols[5]) else { continue }
                let count = cols[1].utf8.reduce(1) { $1 == 0x20 ? $0 + 1 : $0 }
                list.append(LexEntry(
                    phrase: cols[0],
                    syllableText: cols[1],
                    syllableCount: count,
                    xiaohe: cols[2],
                    quanpin: cols[3],
                    gloss: cols[4],
                    freq: freq
                ))
            }
        }
        return list
    }

    private func index(_ list: [LexEntry]) {
        entries = list
        var total = 0.0
        var xMap: [String: [Int]] = [:]
        var qMap: [String: [Int]] = [:]
        xMap.reserveCapacity(list.count)
        qMap.reserveCapacity(list.count)
        for (idx, entry) in list.enumerated() {
            total += Double(max(entry.freq, 0))
            xMap[entry.xiaohe, default: []].append(idx)
            qMap[entry.quanpin, default: []].append(idx)
        }
        let byFreq: (Int, Int) -> Bool = { list[$0].freq > list[$1].freq }
        let sortedX = xMap.mapValues { $0.count > 1 ? $0.sorted(by: byFreq) : $0 }
        let sortedQ = qMap.mapValues { $0.count > 1 ? $0.sorted(by: byFreq) : $0 }
        logTotal = log(max(total, 1))
        byCode = [.xiaohe: sortedX, .quanpin: sortedQ]
        sortedCodes = [.xiaohe: sortedX.keys.sorted(), .quanpin: sortedQ.keys.sorted()]
    }
}

import Foundation
import zlib

struct LexEntry {
    let phrase: String
    let syllables: [String]
    let xiaohe: String
    let quanpin: String
    let gloss: String
    let freq: Int

    var syllableCount: Int { syllables.count }
}

enum GzipInflate {
    static func decompress(_ data: Data) -> Data? {
        guard data.count > 10, data[0] == 0x1f, data[1] == 0x8b else { return nil }
        var stream = z_stream()
        var status = inflateInit2_(&stream, 15 + 16, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        return data.withUnsafeBytes { raw -> Data? in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress else { return nil }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            var output = Data()
            let chunk = 64 * 1024
            var buffer = [UInt8](repeating: 0, count: chunk)
            var inflateStatus = Z_OK
            repeat {
                stream.next_out = UnsafeMutablePointer(&buffer)
                stream.avail_out = uInt(buffer.count)
                inflateStatus = inflate(&stream, Z_NO_FLUSH)
                let produced = buffer.count - Int(stream.avail_out)
                if produced > 0 {
                    output.append(buffer, count: produced)
                }
            } while inflateStatus == Z_OK
            return inflateStatus == Z_STREAM_END ? output : nil
        }
    }
}

final class Lexicon {
    static let shared = Lexicon()

    private(set) var entries: [LexEntry] = []
    private var byXiaohe: [String: [Int]] = [:]
    private var byQuanpin: [String: [Int]] = [:]
    private var xiaoheKeys: [String] = []
    private var quanpinKeys: [String] = []

    private init() {
        load()
    }

    func exactXiaohe(_ code: String) -> [LexEntry] {
        (byXiaohe[code] ?? []).map { entries[$0] }
    }

    func exactQuanpin(_ code: String) -> [LexEntry] {
        (byQuanpin[code] ?? []).map { entries[$0] }
    }

    func prefixXiaohe(_ prefix: String) -> [LexEntry] {
        prefixEntries(keys: xiaoheKeys, map: byXiaohe, prefix: prefix)
    }

    func prefixQuanpin(_ prefix: String) -> [LexEntry] {
        prefixEntries(keys: quanpinKeys, map: byQuanpin, prefix: prefix)
    }

    private func prefixEntries(keys: [String], map: [String: [Int]], prefix: String) -> [LexEntry] {
        guard !prefix.isEmpty else { return [] }
        var lo = 0
        var hi = keys.count
        while lo < hi {
            let mid = (lo + hi) / 2
            if keys[mid] < prefix {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        var out: [LexEntry] = []
        var i = lo
        while i < keys.count, keys[i].hasPrefix(prefix) {
            for idx in map[keys[i]] ?? [] {
                out.append(entries[idx])
            }
            i += 1
            if out.count >= 80 { break }
        }
        return out
    }

    private func load() {
        guard let url = Bundle.main.url(forResource: "cedict", withExtension: "tsv.gz", subdirectory: "Resources")
                ?? Bundle.main.url(forResource: "cedict", withExtension: "tsv.gz") else {
            NSLog("Ciji: cedict.tsv.gz not found in bundle")
            return
        }
        guard let gz = try? Data(contentsOf: url), let raw = GzipInflate.decompress(gz),
              let text = String(data: raw, encoding: .utf8) else {
            NSLog("Ciji: failed to inflate cedict.tsv.gz")
            return
        }
        var list: [LexEntry] = []
        list.reserveCapacity(130_000)
        text.enumerateLines { line, _ in
            if line.isEmpty || line.hasPrefix("#") { return }
            let cols = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard cols.count >= 6, let freq = Int(cols[5]) else { return }
            list.append(
                LexEntry(
                    phrase: cols[0],
                    syllables: cols[1].split(separator: " ").map(String.init),
                    xiaohe: cols[2],
                    quanpin: cols[3],
                    gloss: cols[4],
                    freq: freq
                )
            )
        }
        entries = list
        var xMap: [String: [Int]] = [:]
        var qMap: [String: [Int]] = [:]
        xMap.reserveCapacity(list.count)
        qMap.reserveCapacity(list.count)
        for (idx, entry) in list.enumerated() {
            xMap[entry.xiaohe, default: []].append(idx)
            qMap[entry.quanpin, default: []].append(idx)
        }
        byXiaohe = xMap
        byQuanpin = qMap
        xiaoheKeys = xMap.keys.sorted()
        quanpinKeys = qMap.keys.sorted()
        NSLog("Ciji: loaded \(list.count) lexicon entries")
    }
}

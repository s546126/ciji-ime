import AppKit

/// Two-way bridge to Relingo (https://relingo.net), the browser vocabulary tool.
///
/// * Pull: the English words in your Relingo 生词本 are cached locally; candidates
///   whose English gloss hits one get an "R" badge, so the IME reminds you of
///   words you are learning in Relingo while you type Chinese.
/// * Push: Ctrl+S in the IME also adds the candidate's English headword to Relingo.
/// * Files: export/import plain word lists when no token is configured.
///
/// Relingo has no public API; this uses the same endpoints as the extension
/// (api.relingo.net/api, `x-relingo-token`), as documented by the open-source
/// relingo-desktop client. Pushes merge with the existing list, never replace it.
final class RelingoSync {
    static let shared = RelingoSync()

    private(set) var words: Set<String> = []
    private(set) var status = "未连接"
    private var lastPull = Date.distantPast
    private let session: URLSession
    private let base = URL(string: "https://api.relingo.net/api")!

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
        if let data = try? Data(contentsOf: Self.cacheURL()),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            words = Set(list)
            status = "本地缓存 \(words.count) 词"
        }
    }

    static func cacheURL() -> URL {
        AppConfig.supportDirectory().appendingPathComponent("relingo-words.json")
    }

    static func exportURL() -> URL {
        AppConfig.supportDirectory().appendingPathComponent("relingo-import.txt")
    }

    /// English headword used for Relingo: "to translate; to interpret" -> "translate".
    static func headword(_ gloss: String) -> String? {
        Lexicon.englishKeys(gloss).first(where: { !$0.0.contains(" ") })?.0
    }

    func matches(_ gloss: String) -> Bool {
        guard !words.isEmpty, !gloss.isEmpty else { return false }
        return Lexicon.englishKeys(gloss).contains { words.contains($0.0) }
    }

    // MARK: API

    private struct ListItem {
        let id: String
        let type: String
        let name: String
    }

    private func call(_ path: String, body: [String: Any], token: String, done: @escaping (Any?) -> Void) {
        var request = URLRequest(url: base.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "x-relingo-token")
        request.setValue("cn", forHTTPHeaderField: "x-relingo-lang")
        session.dataTask(with: request) { data, _, error in
            var payload: Any?
            if let data, let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if (root["code"] as? Int ?? -1) == 0 {
                    payload = root["data"]
                } else {
                    NSLog("Ciji Relingo \(path): \(root["message"] ?? "error")")
                }
            } else if let error {
                NSLog("Ciji Relingo \(path): \(error.localizedDescription)")
            }
            DispatchQueue.main.async { done(payload) }
        }.resume()
    }

    private func lists(token: String, done: @escaping ([ListItem]?) -> Void) {
        call("getVocabularyList", body: [:], token: token) { data in
            guard let arr = data as? [[String: Any]] else { return done(nil) }
            done(arr.compactMap { d in
                let id = (d["id"] as? String) ?? (d["_id"] as? String) ?? ""
                guard !id.isEmpty else { return nil }
                return ListItem(id: id, type: d["type"] as? String ?? "", name: d["name"] as? String ?? "")
            })
        }
    }

    private func vocabulary(_ item: ListItem, token: String, done: @escaping ([String]?) -> Void) {
        call("getVocabulary", body: ["id": item.id, "type": item.type], token: token) { data in
            done((data as? [String: Any])?["words"] as? [String])
        }
    }

    /// The list Ctrl+S pushes to: config `relingo.vocabularyId`, else the first
    /// list that is not the built-in "mastered" one.
    private func target(in lists: [ListItem], config: RelingoConfig) -> ListItem? {
        if !config.vocabularyId.isEmpty {
            return lists.first { $0.id == config.vocabularyId }
        }
        return lists.first { $0.type != "mastered" && $0.type != "system" }
    }

    /// Refreshes the cached word set (at most every 10 minutes unless forced).
    func pull(force: Bool = false, done: ((String) -> Void)? = nil) {
        let config = AppConfig.load().relingo
        guard !config.token.isEmpty else {
            status = words.isEmpty ? "未连接（config.json → relingo.token）" : "本地词表 \(words.count) 词"
            done?(status)
            return
        }
        guard force || Date().timeIntervalSince(lastPull) > 600 else { done?(status); return }
        lastPull = Date()
        lists(token: config.token) { [weak self] lists in
            guard let self else { return }
            guard let lists else {
                self.status = "连接失败（检查 token）"
                done?(self.status)
                return
            }
            let wanted = lists.filter { $0.type != "mastered" && $0.type != "system" }
            var collected = Set<String>()
            let group = DispatchGroup()
            for item in wanted {
                group.enter()
                self.vocabulary(item, token: config.token) { list in
                    for w in list ?? [] { collected.insert(w.lowercased()) }
                    group.leave()
                }
            }
            group.notify(queue: .main) {
                self.words = collected
                self.saveCache()
                let names = wanted.map { "\($0.name)(\($0.id))" }.joined(separator: ", ")
                self.status = "已同步 \(collected.count) 词 · \(names)"
                done?(self.status)
            }
        }
    }

    /// Adds English words to the Relingo list (fetch, merge, submit).
    func push(_ newWords: [String], done: ((String) -> Void)? = nil) {
        let cleaned = newWords.map { $0.lowercased() }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { return }
        words.formUnion(cleaned)
        saveCache()
        let config = AppConfig.load().relingo
        guard !config.token.isEmpty, config.autoPush else { return }
        lists(token: config.token) { [weak self] lists in
            guard let self, let lists, let target = self.target(in: lists, config: config) else {
                self?.status = "推送失败：找不到 Relingo 生词本"
                done?(self?.status ?? "")
                return
            }
            self.vocabulary(target, token: config.token) { existing in
                guard let existing else {
                    self.status = "推送失败：读取生词本出错"
                    done?(self.status)
                    return
                }
                let merged = Array(Set(existing.map { $0.lowercased() }).union(cleaned)).sorted()
                self.call("submitVocabulary", body: ["id": target.id, "type": target.type, "words": merged], token: config.token) { data in
                    self.status = data == nil ? "推送失败" : "已推送到 Relingo「\(target.name)」"
                    done?(self.status)
                }
            }
        }
    }

    // MARK: files

    /// Plain word list (one per line) for Relingo / any vocabulary app.
    func exportWordList() -> URL {
        var set = words
        for item in VocabBook.shared.items.values {
            if let w = Self.headword(item.gloss) { set.insert(w) }
        }
        let url = Self.exportURL()
        try? FileManager.default.createDirectory(at: AppConfig.supportDirectory(), withIntermediateDirectories: true)
        try? (set.sorted().joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Imports English words from a Relingo export (txt/csv: first column).
    func importFile(_ url: URL) -> Int {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return 0 }
        var added = 0
        for line in text.split(whereSeparator: \.isNewline) {
            let first = line.split(whereSeparator: { $0 == "," || $0 == "\t" || $0 == ";" }).first ?? ""
            let word = first.trimmingCharacters(in: CharacterSet(charactersIn: "\"' ").union(.whitespaces)).lowercased()
            guard !word.isEmpty, word.count <= 40,
                  word.unicodeScalars.allSatisfy({ ("a"..."z").contains($0) || $0 == "-" || $0 == "'" || $0 == " " })
            else { continue }
            if words.insert(word).inserted { added += 1 }
        }
        saveCache()
        status = "本地词表 \(words.count) 词"
        return added
    }

    private func saveCache() {
        let list = words.sorted()
        DispatchQueue.global(qos: .utility).async {
            try? FileManager.default.createDirectory(at: AppConfig.supportDirectory(), withIntermediateDirectories: true)
            if let data = try? JSONEncoder().encode(list) {
                try? data.write(to: Self.cacheURL(), options: .atomic)
            }
        }
    }
}

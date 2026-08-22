import Foundation

/// Fetches short English glosses from a CLIProxyAPI (OpenAI-compatible) endpoint.
/// Never blocks the typing path: CEDICT glosses show immediately; the network
/// result patches the visible page when it arrives.
final class GlossService {
    static let shared = GlossService()

    private let session: URLSession
    private let queue = DispatchQueue(label: "com.shengtao.ciji.gloss")
    private var memory: [String: String] = [:]
    private var disk: [String: String] = [:]
    private var generation: UInt64 = 0

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 1.6
        config.timeoutIntervalForResource = 1.8
        session = URLSession(configuration: config)
        disk = Self.loadDiskCache()
        memory.merge(disk) { current, _ in current }
    }

    func cachedGloss(for phrase: String) -> String? {
        queue.sync { memory[phrase] }
    }

    func rememberLocal(phrase: String, gloss: String) {
        guard !gloss.isEmpty else { return }
        queue.async {
            if self.memory[phrase] == nil {
                self.memory[phrase] = gloss
            }
        }
    }

    func request(
        phrases: [String],
        fallback: [String: String],
        token: UInt64,
        completion: @escaping ([String: String]) -> Void
    ) {
        let unique = Array(Set(phrases.filter { !$0.isEmpty }))
        guard !unique.isEmpty else { return }

        var immediate: [String: String] = [:]
        var missing: [String] = []
        queue.sync {
            for phrase in unique {
                if let hit = memory[phrase], !hit.isEmpty {
                    immediate[phrase] = hit
                } else if let local = fallback[phrase], !local.isEmpty {
                    immediate[phrase] = local
                    memory[phrase] = local
                } else {
                    missing.append(phrase)
                }
            }
        }
        if !immediate.isEmpty {
            DispatchQueue.main.async { completion(immediate) }
        }

        let cfg = AppConfig.load()
        guard cfg.hasProxy, let url = AppConfig.chatCompletionsURL(from: cfg.proxyBaseURL) else {
            return
        }
        let need = unique.filter { immediate[$0] == nil || missing.contains($0) }
        // Still refresh the visible page when a proxy is configured, but skip
        // phrases already filled by a previous LLM response (disk/memory).
        let pending = unique.filter { phrase in
            queue.sync {
                disk[phrase] == nil && (memory[phrase] == nil || fallback[phrase] == memory[phrase])
            }
        }
        guard !pending.isEmpty else { return }

        let model = cfg.model.isEmpty ? AppConfig.defaultModel : cfg.model
        let listed = pending.joined(separator: "、")
        let user = "Phrases: \(listed)"
        let system = "Translate each Chinese phrase into a short English dictionary gloss (2-5 words). Reply with a JSON object mapping phrase to gloss only."
        let body: [String: Any] = [
            "model": model,
            "temperature": 0,
            "max_tokens": 200,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty {
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }

        let captured = token
        session.dataTask(with: request) { [weak self] data, _, _ in
            guard let self, let data else { return }
            guard let parsed = Self.parseGlosses(data) else { return }
            self.queue.async {
                guard captured == self.generation else { return }
                for (phrase, gloss) in parsed where !gloss.isEmpty {
                    self.memory[phrase] = gloss
                    self.disk[phrase] = gloss
                }
                Self.saveDiskCache(self.disk)
                DispatchQueue.main.async {
                    completion(parsed)
                }
            }
        }.resume()
        _ = need
    }

    func bumpGeneration() -> UInt64 {
        queue.sync {
            generation += 1
            return generation
        }
    }

    private static func parseGlosses(_ data: Data) -> [String: String]? {
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let choices = root["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let content = message["content"] as? String
        else { return nil }
        var text = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text.replacingOccurrences(of: "```json", with: "")
            text = text.replacingOccurrences(of: "```", with: "")
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: String] {
            return obj
        }
        if let obj = try? JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any] {
            var out: [String: String] = [:]
            for (k, v) in obj {
                out[k] = String(describing: v)
            }
            return out
        }
        return nil
    }

    private static func cacheURL() -> URL {
        AppConfig.supportDirectory().appendingPathComponent("gloss-cache.json")
    }

    private static func loadDiskCache() -> [String: String] {
        guard let data = try? Data(contentsOf: cacheURL()),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return obj
    }

    private static func saveDiskCache(_ cache: [String: String]) {
        AppConfig.ensureSupportFiles()
        if let data = try? JSONSerialization.data(withJSONObject: cache, options: [.prettyPrinted]) {
            try? data.write(to: cacheURL())
        }
    }
}

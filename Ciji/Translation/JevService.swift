import Foundation

/// Context-aware candidate reranking with a TypeSafe "System One" decision model
/// (Jev via OpenRouter, or any gateway speaking the same protocol, e.g. Laya).
///
/// Same idea as jev-rime-rerank: send the text before the cursor plus the top
/// candidates, ask which completion is the most natural Chinese, and reorder by
/// the returned probabilities. Unlike the Rime filter this runs automatically:
/// debounced, off the typing path, and the panel refreshes when the answer lands.
final class JevService {
    static let shared = JevService()

    private let session: URLSession
    private var pending: DispatchWorkItem?
    private var generation = 0
    private var cache: [String: [String]] = [:]
    private var cacheKeys: [String] = []
    private let cacheLimit = 400

    /// Shown in the menu so users can tell whether Jev is working.
    private(set) var status = "未配置"
    private(set) var calls = 0

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 3
        config.timeoutIntervalForResource = 4
        session = URLSession(configuration: config)
    }

    func cancel() {
        pending?.cancel()
        pending = nil
        generation += 1
    }

    /// Main thread only. `completion` gets the phrases best-first, on the main thread.
    func rerank(
        context: String,
        input: String,
        phrases: [String],
        config: AppConfig,
        immediate: Bool = false,
        completion: @escaping ([String]) -> Void
    ) {
        cancel()
        guard phrases.count >= 2 else { return }
        guard let endpoint = config.jev.endpoint(fallbackKey: config.apiKey, fallbackBase: config.proxyBaseURL) else {
            status = config.jev.enabled ? "未配置（config.json → jev.apiKey）" : "已关闭"
            return
        }
        let cacheKey = context + "\u{1}" + input + "\u{1}" + phrases.joined(separator: "|")
        if let hit = cache[cacheKey] {
            completion(hit)
            return
        }
        let jev = config.jev
        let token = generation
        let work = DispatchWorkItem { [weak self] in
            self?.send(url: endpoint.0, key: endpoint.1, jev: jev, context: context, phrases: phrases) { order in
                guard let self, token == self.generation, let order else { return }
                self.remember(cacheKey, order)
                completion(order)
            }
        }
        pending = work
        let delay = immediate ? 0 : max(0, jev.debounceMs)
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(delay), execute: work)
    }

    private func remember(_ key: String, _ order: [String]) {
        if cache[key] == nil {
            cacheKeys.append(key)
            if cacheKeys.count > cacheLimit {
                cache.removeValue(forKey: cacheKeys.removeFirst())
            }
        }
        cache[key] = order
    }

    static func requestBody(context: String, phrases: [String], model: String?) -> [String: Any] {
        var criteria: [String: String] = [:]
        for p in phrases { criteria[p] = context + p }
        var body: [String: Any] = [
            "state": "A Chinese sentence being typed with a pinyin IME. Prefix so far: \(context.isEmpty ? "(start of text)" : context)",
            "questions": [
                "next": [
                    "type": "choice",
                    "instructions": "Which completed sentence is the most natural, fluent Chinese?",
                    "criteria": criteria,
                ] as [String: Any],
            ],
        ]
        if let model, !model.isEmpty { body["model"] = model }
        return body
    }

    private func send(
        url: URL,
        key: String,
        jev: JevConfig,
        context: String,
        phrases: [String],
        done: @escaping ([String]?) -> Void
    ) {
        // Gateways inject the model themselves; OpenRouter needs it in the body.
        let body = Self.requestBody(context: context, phrases: phrases, model: jev.isGateway ? nil : jev.model)
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else { return done(nil) }
        var request = URLRequest(url: url, timeoutInterval: Double(max(300, jev.timeoutMs)) / 1000)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.setValue("https://github.com/s546126/ciji-ime", forHTTPHeaderField: "HTTP-Referer")
        request.setValue("Ciji IME", forHTTPHeaderField: "X-Title")
        calls += 1
        let started = Date()
        session.dataTask(with: request) { [weak self] data, response, error in
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            let order = data.flatMap { Self.parseOrder($0, phrases: phrases) }
            DispatchQueue.main.async {
                guard let self else { return }
                let ms = Int(Date().timeIntervalSince(started) * 1000)
                if let order {
                    self.status = "正常（\(ms) ms）"
                    done(order)
                } else {
                    if let error {
                        self.status = "失败：\(error.localizedDescription)"
                    } else {
                        let snippet = data.flatMap { String(data: $0.prefix(120), encoding: .utf8) } ?? ""
                        self.status = "失败：HTTP \(code) \(snippet)"
                    }
                    NSLog("Ciji Jev: \(self.status)")
                    done(nil)
                }
            }
        }.resume()
    }

    /// Accepts the System One shape `{"answers":{"next":{"probabilities":{…}}}}`
    /// and tolerates wrappers (a top-level `decision`/`result`, or just a chosen label).
    static func parseOrder(_ data: Data, phrases: [String]) -> [String]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) else { return nil }
        var probs: [String: Double] = [:]
        var chosen: String?

        func walk(_ node: Any, depth: Int) {
            guard depth < 6 else { return }
            if let dict = node as? [String: Any] {
                if let p = dict["probabilities"] as? [String: Any] {
                    for (k, v) in p {
                        if let d = v as? Double { probs[k] = d } else if let n = v as? NSNumber { probs[k] = n.doubleValue }
                    }
                }
                for key in ["answer", "choice", "value", "selected"] {
                    if chosen == nil, let s = dict[key] as? String, phrases.contains(s) { chosen = s }
                }
                for (_, v) in dict { walk(v, depth: depth + 1) }
            } else if let list = node as? [Any] {
                for v in list { walk(v, depth: depth + 1) }
            }
        }
        walk(root, depth: 0)

        if probs.isEmpty, let chosen {
            probs[chosen] = 1
        }
        guard !probs.isEmpty else { return nil }
        let index = Dictionary(uniqueKeysWithValues: phrases.enumerated().map { ($1, $0) })
        return phrases.sorted {
            let a = probs[$0] ?? -1
            let b = probs[$1] ?? -1
            if a != b { return a > b }
            return index[$0, default: 0] < index[$1, default: 0]
        }
    }
}

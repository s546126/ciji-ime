import Foundation

/// Whole-sentence Chinese → English via the configured OpenAI-compatible
/// endpoint (CLIProxyAPI, OpenRouter, …). Without one, falls back to the
/// word-by-word gloss so Ctrl+T always shows something.
final class TranslateService {
    static let shared = TranslateService()

    private let session: URLSession
    private var cache: [String: String] = [:]
    private var generation = 0

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 10
        session = URLSession(configuration: config)
    }

    /// Main thread in, main thread out. `completion(text, isAI)`.
    func translate(_ chinese: String, fallback: String, completion: @escaping (String, Bool) -> Void) {
        generation += 1
        let token = generation
        if let hit = cache[chinese] {
            completion(hit, true)
            return
        }
        let cfg = AppConfig.load()
        guard cfg.hasProxy, let url = AppConfig.chatCompletionsURL(from: cfg.proxyBaseURL) else {
            completion(fallback, false)
            return
        }
        let body: [String: Any] = [
            "model": cfg.model.isEmpty ? AppConfig.defaultModel : cfg.model,
            "temperature": 0,
            "max_tokens": 200,
            "messages": [
                ["role": "system", "content": "Translate the user's Chinese text into natural, idiomatic English. Reply with the translation only, no quotes or notes."],
                ["role": "user", "content": chinese],
            ],
        ]
        guard let payload = try? JSONSerialization.data(withJSONObject: body) else {
            completion(fallback, false)
            return
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = payload
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let key = cfg.apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        session.dataTask(with: request) { [weak self] data, _, _ in
            var text: String?
            if let data,
               let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let choices = root["choices"] as? [[String: Any]],
               let message = choices.first?["message"] as? [String: Any],
               let content = message["content"] as? String {
                text = content.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            DispatchQueue.main.async {
                guard let self, token == self.generation else { return }
                if let text, !text.isEmpty {
                    self.cache[chinese] = text
                    completion(text, true)
                } else {
                    completion(fallback, false)
                }
            }
        }.resume()
    }
}

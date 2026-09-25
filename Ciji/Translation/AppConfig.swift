import Foundation

struct AppConfig: Equatable, Codable {
    var proxyBaseURL: String
    var apiKey: String
    var model: String
    var scheme: String?
    var jev: JevConfig
    var relingo: RelingoConfig

    enum CodingKeys: String, CodingKey {
        case proxyBaseURL
        case apiKey
        case model
        case scheme
        case jev
        case relingo
    }

    static let defaultModel = "gemini-2.5-flash"

    init(
        proxyBaseURL: String = "",
        apiKey: String = "",
        model: String = AppConfig.defaultModel,
        scheme: String? = "xiaohe",
        jev: JevConfig = JevConfig(),
        relingo: RelingoConfig = RelingoConfig()
    ) {
        self.proxyBaseURL = proxyBaseURL
        self.apiKey = apiKey
        self.model = model
        self.scheme = scheme
        self.jev = jev
        self.relingo = relingo
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proxyBaseURL = try container.decodeIfPresent(String.self, forKey: .proxyBaseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? AppConfig.defaultModel
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
        jev = (try? container.decodeIfPresent(JevConfig.self, forKey: .jev)) ?? JevConfig()
        relingo = (try? container.decodeIfPresent(RelingoConfig.self, forKey: .relingo)) ?? RelingoConfig()
    }

    static var empty: AppConfig {
        AppConfig(proxyBaseURL: "", apiKey: "", model: defaultModel, scheme: "xiaohe")
    }

    var hasProxy: Bool {
        !proxyBaseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var preferredScheme: Scheme {
        scheme == "quanpin" ? .quanpin : .xiaohe
    }

    static func supportDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("Ciji", isDirectory: true)
    }

    static func configURL() -> URL {
        supportDirectory().appendingPathComponent("config.json")
    }

    static func sampleURL() -> URL? {
        Bundle.main.url(forResource: "config.sample", withExtension: "json")
            ?? Bundle.main.url(forResource: "config.sample", withExtension: "json", subdirectory: "Resources")
    }

    private static var cached: (date: Date, config: AppConfig)?

    /// Cached by modification date: called on every keystroke via GlossService.
    static func load() -> AppConfig {
        let url = configURL()
        let modified = (try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate]) as? Date
        if let modified, let cached, cached.date == modified {
            return cached.config
        }
        let config = loadFromDisk(url)
        if let modified {
            cached = (modified, config)
        }
        return config
    }

    private static func loadFromDisk(_ url: URL) -> AppConfig {
        ensureSupportFiles()
        guard let data = try? Data(contentsOf: url) else { return .empty }
        let decoder = JSONDecoder()
        if let parsed = try? decoder.decode(AppConfig.self, from: data) {
            var cfg = parsed
            if cfg.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                cfg.model = defaultModel
            }
            return cfg
        }
        return .empty
    }

    static func ensureSupportFiles() {
        let dir = supportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = configURL()
        if !FileManager.default.fileExists(atPath: dest.path), let sample = sampleURL() {
            try? FileManager.default.copyItem(at: sample, to: dest)
        } else if !FileManager.default.fileExists(atPath: dest.path) {
            let data = try? JSONEncoder().encode(AppConfig.empty)
            try? data?.write(to: dest)
        }
    }

    /// Accepts `http://host:8317`, `.../v1`, or a full `.../v1/chat/completions`.
    static func chatCompletionsURL(from base: String) -> URL? {
        var s = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") {
            s.removeLast()
        }
        guard !s.isEmpty else { return nil }
        if s.hasSuffix("/chat/completions") {
            return URL(string: s)
        }
        if s.hasSuffix("/v1") {
            return URL(string: s + "/chat/completions")
        }
        return URL(string: s + "/v1/chat/completions")
    }

    func savingScheme(_ scheme: Scheme) -> AppConfig {
        var copy = self
        copy.scheme = scheme.rawValue
        return copy
    }

    func persist() {
        let dir = AppConfig.supportDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(self) {
            try? data.write(to: AppConfig.configURL())
        }
        AppConfig.cached = nil
    }
}

/// Jev (TypeSafe System One) context reranking. See JevService.
struct JevConfig: Equatable, Codable {
    /// Turned on by default, but it only runs once a key (or gateway URL) is set.
    var enabled = true
    /// "openrouter" → https://openrouter.ai/api/alpha/decisions; "gateway" → `url` (e.g. a Sherlock/Laya …/decide).
    var provider = "openrouter"
    var apiKey = ""
    var url = ""
    var model = "typesafe/jev-1.13"
    var candidates = 6
    var debounceMs = 150
    var timeoutMs = 1500

    enum CodingKeys: String, CodingKey {
        case enabled, provider, apiKey, url, model, candidates, debounceMs, timeoutMs
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        provider = try c.decodeIfPresent(String.self, forKey: .provider) ?? "openrouter"
        apiKey = try c.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? ""
        model = try c.decodeIfPresent(String.self, forKey: .model) ?? "typesafe/jev-1.13"
        candidates = try c.decodeIfPresent(Int.self, forKey: .candidates) ?? 6
        debounceMs = try c.decodeIfPresent(Int.self, forKey: .debounceMs) ?? 150
        timeoutMs = try c.decodeIfPresent(Int.self, forKey: .timeoutMs) ?? 1500
    }

    static let openRouterDecisions = "https://openrouter.ai/api/alpha/decisions"

    var isGateway: Bool { provider.lowercased() == "gateway" }

    /// Endpoint and key to call, or nil when Jev is off / not configured.
    func endpoint(fallbackKey: String, fallbackBase: String) -> (URL, String)? {
        guard enabled else { return nil }
        var key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if isGateway {
            guard let u = URL(string: url.trimmingCharacters(in: .whitespacesAndNewlines)), u.scheme != nil else { return nil }
            return (u, key)
        }
        // Reuse the AI key when the AI endpoint is OpenRouter too.
        if key.isEmpty, fallbackBase.contains("openrouter.ai") {
            key = fallbackKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !key.isEmpty else { return nil }
        let custom = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let u = URL(string: custom.isEmpty ? Self.openRouterDecisions : custom) else { return nil }
        return (u, key)
    }
}

/// Relingo sync. `token` is the `x-relingo-token` the Relingo extension sends
/// (browser DevTools → Network → any api.relingo.net request).
struct RelingoConfig: Equatable, Codable {
    var token = ""
    /// Target 生词本 id for pushes; empty = first non-"mastered" list.
    var vocabularyId = ""
    /// Ctrl+S also adds the English word to Relingo.
    var autoPush = true

    enum CodingKeys: String, CodingKey {
        case token, vocabularyId, autoPush
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        token = try c.decodeIfPresent(String.self, forKey: .token) ?? ""
        vocabularyId = try c.decodeIfPresent(String.self, forKey: .vocabularyId) ?? ""
        autoPush = try c.decodeIfPresent(Bool.self, forKey: .autoPush) ?? true
    }
}

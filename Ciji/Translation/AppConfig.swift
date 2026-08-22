import Foundation

struct AppConfig: Equatable, Codable {
    var proxyBaseURL: String
    var apiKey: String
    var model: String
    var scheme: String?

    enum CodingKeys: String, CodingKey {
        case proxyBaseURL
        case apiKey
        case model
        case scheme
    }

    static let defaultModel = "gemini-2.5-flash"

    init(
        proxyBaseURL: String = "",
        apiKey: String = "",
        model: String = AppConfig.defaultModel,
        scheme: String? = "xiaohe"
    ) {
        self.proxyBaseURL = proxyBaseURL
        self.apiKey = apiKey
        self.model = model
        self.scheme = scheme
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        proxyBaseURL = try container.decodeIfPresent(String.self, forKey: .proxyBaseURL) ?? ""
        apiKey = try container.decodeIfPresent(String.self, forKey: .apiKey) ?? ""
        model = try container.decodeIfPresent(String.self, forKey: .model) ?? AppConfig.defaultModel
        scheme = try container.decodeIfPresent(String.self, forKey: .scheme)
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

    static func load() -> AppConfig {
        ensureSupportFiles()
        let url = configURL()
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
    }
}

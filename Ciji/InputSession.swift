import AppKit
import InputMethodKit

final class SessionStore {
    static let shared = SessionStore()
    private let table = NSMapTable<AnyObject, InputSession>.weakToStrongObjects()
    private let fallback = InputSession()
    weak var active: InputSession?

    /// Menu and other UI must not wait for IMK `activateServer`.
    /// Until a client session exists, pin and return the process-wide fallback.
    func current() -> InputSession {
        if let active {
            return active
        }
        active = fallback
        return fallback
    }

    func session(for client: Any?) -> InputSession {
        guard let object = client as AnyObject? else { return fallback }
        if let existing = table.object(forKey: object) {
            active = existing
            return existing
        }
        let created = InputSession()
        table.setObject(created, forKey: object)
        active = created
        return created
    }
}

final class InputSession {
    private var keys = ""
    private var candidates: [Candidate] = []
    private var selected = 0
    private var page = 0
    private let pageSize = 9
    private var asciiMode = false
    private var scheme: Scheme = AppConfig.load().preferredScheme
    private var glossToken: UInt64 = 0

    private static let punct: [String: String] = [
        ",": "，",
        ".": "。",
        "?": "？",
        "!": "！",
        ";": "；",
        ":": "：",
        "\\": "、",
        "^": "……",
        "<": "《",
        ">": "》",
        "(": "（",
        ")": "）",
        "[": "【",
        "]": "】",
        "{": "『",
        "}": "』",
        "`": "·",
        "$": "￥",
        "~": "～",
        "@": "@",
        "'": "‘",
        "\"": "“",
    ]

    var currentScheme: Scheme { scheme }
    var isASCII: Bool { asciiMode }

    func activate() {
        AppConfig.ensureSupportFiles()
        scheme = AppConfig.load().preferredScheme
    }

    func deactivate() {
        clear(commit: false, client: nil)
        CandidatePanel.shared.hide()
    }

    func commitIfNeeded(client: IMKTextInput?) {
        if !keys.isEmpty {
            commitIndex(0, client: client, insertRemainingRaw: false)
        }
    }

    func handle(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        if event.type == .flagsChanged {
            return handleFlags(event)
        }
        guard event.type == .keyDown else { return false }

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.control), mods.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "p" {
            toggleScheme(client: client)
            return true
        }
        if mods.contains(.command) {
            return false
        }
        if mods.contains(.control) {
            return false
        }

        if event.keyCode == 0x39 { // Caps Lock
            setASCII(!asciiMode, client: client)
            return true
        }

        if asciiMode {
            return false
        }

        if event.keyCode == 53 { // escape
            if keys.isEmpty { return false }
            clear(commit: false, client: client)
            return true
        }
        if event.keyCode == 51 { // delete
            if keys.isEmpty { return false }
            keys.removeLast()
            refresh(client: client)
            return true
        }
        if event.keyCode == 36 || event.keyCode == 76 { // return / keypad enter
            if keys.isEmpty { return false }
            if !visibleCandidates().isEmpty {
                commitIndex(selected, client: client, insertRemainingRaw: false)
            } else {
                insert(keys, client: client)
                clear(commit: false, client: client)
            }
            return true
        }

        let chars = event.charactersIgnoringModifiers ?? ""
        if keys.isEmpty == false {
            if chars == " " {
                commitIndex(0, client: client, insertRemainingRaw: false)
                return true
            }
            if chars == "-" {
                page(delta: -1, client: client)
                return true
            }
            if chars == "=" {
                page(delta: 1, client: client)
                return true
            }
            if let number = Int(chars), (1...9).contains(number) {
                commitIndex(number - 1, client: client, insertRemainingRaw: false)
                return true
            }
        }

        if let first = chars.lowercased().first, first.isLetter, first.isASCII {
            keys.append(first)
            selected = 0
            page = 0
            refresh(client: client)
            return true
        }

        if let mapped = Self.punct[chars] ?? Self.punct[event.characters ?? ""] {
            if !keys.isEmpty {
                commitIndex(0, client: client, insertRemainingRaw: false)
            }
            insert(mapped, client: client)
            return true
        }

        if !keys.isEmpty, let raw = event.characters, !raw.isEmpty {
            commitIndex(0, client: client, insertRemainingRaw: false)
            insert(raw, client: client)
            return true
        }
        return false
    }

    func menu() -> NSMenu {
        let menu = NSMenu(title: "词记")
        menu.autoenablesItems = false
        let target = NSApp.delegate
        let xiaohe = NSMenuItem(title: "小鹤双拼", action: #selector(AppDelegate.selectXiaohe(_:)), keyEquivalent: "")
        xiaohe.state = scheme == .xiaohe ? .on : .off
        xiaohe.target = target
        let quanpin = NSMenuItem(title: "全拼", action: #selector(AppDelegate.selectQuanpin(_:)), keyEquivalent: "")
        quanpin.state = scheme == .quanpin ? .on : .off
        quanpin.target = target
        let ascii = NSMenuItem(title: "英文 ASCII", action: #selector(AppDelegate.toggleASCII(_:)), keyEquivalent: "")
        ascii.state = asciiMode ? .on : .off
        ascii.target = target
        let config = NSMenuItem(title: "打开配置文件夹", action: #selector(AppDelegate.openConfig(_:)), keyEquivalent: "")
        config.target = target
        menu.addItem(xiaohe)
        menu.addItem(quanpin)
        menu.addItem(ascii)
        menu.addItem(.separator())
        menu.addItem(config)
        return menu
    }

    func setScheme(_ newScheme: Scheme, client: IMKTextInput?) {
        scheme = newScheme
        var cfg = AppConfig.load()
        cfg.scheme = newScheme.rawValue
        cfg.persist()
        page = 0
        selected = 0
        refresh(client: client)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    func toggleScheme(client: IMKTextInput?) {
        setScheme(scheme == .xiaohe ? .quanpin : .xiaohe, client: client)
    }

    func setASCII(_ on: Bool, client: IMKTextInput?) {
        asciiMode = on
        if on {
            clear(commit: false, client: client)
        }
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    func toggleASCII(client: IMKTextInput?) {
        setASCII(!asciiMode, client: client)
    }

    private func handleFlags(_ event: NSEvent) -> Bool {
        if event.keyCode == 0x39 {
            let on = event.modifierFlags.contains(.capsLock)
            setASCII(on, client: nil)
            return true
        }
        return false
    }

    private func visibleCandidates() -> [Candidate] {
        let start = page * pageSize
        guard start < candidates.count else { return [] }
        return Array(candidates[start..<min(start + pageSize, candidates.count)])
    }

    private func page(delta: Int, client: IMKTextInput?) {
        let pages = max(1, Int(ceil(Double(candidates.count) / Double(pageSize))))
        page = (page + delta + pages) % pages
        selected = 0
        render(client: client)
    }

    private func refresh(client: IMKTextInput?) {
        if keys.isEmpty {
            candidates = []
            selected = 0
            page = 0
            mark("", client: client)
            CandidatePanel.shared.hide()
            return
        }
        candidates = InputDecoder.decode(keys: keys, scheme: scheme)
        if page * pageSize >= max(candidates.count, 1) {
            page = 0
        }
        selected = min(selected, max(visibleCandidates().count - 1, 0))
        render(client: client)
        requestGlosses()
    }

    private func render(client: IMKTextInput?) {
        let visible = visibleCandidates()
        let segmented = visible.first?.segmented ?? segmentedKeys()
        mark(segmented, client: client)
        if visible.isEmpty {
            CandidatePanel.shared.hide()
            return
        }
        CandidatePanel.shared.update(
            segmented: segmented,
            candidates: visible,
            selected: selected,
            page: page,
            pageSize: pageSize
        )
        if let caret = caretRect(client: client) {
            CandidatePanel.shared.show(near: caret)
        } else if client != nil {
            CandidatePanel.shared.show(near: NSRect(x: 80, y: 80, width: 1, height: 18))
        } else if !CandidatePanel.shared.isVisible {
            CandidatePanel.shared.show(near: NSRect(x: 80, y: 80, width: 1, height: 18))
        }
    }

    private func requestGlosses() {
        let visible = visibleCandidates()
        guard !visible.isEmpty else { return }
        var fallback: [String: String] = [:]
        var phrases: [String] = []
        for item in visible {
            phrases.append(item.phrase)
            if !item.gloss.isEmpty {
                fallback[item.phrase] = item.gloss
                GlossService.shared.rememberLocal(phrase: item.phrase, gloss: item.gloss)
            }
            if let cached = GlossService.shared.cachedGloss(for: item.phrase) {
                applyGloss(phrase: item.phrase, gloss: cached)
            }
        }
        glossToken = GlossService.shared.bumpGeneration()
        let token = glossToken
        let snapshotKeys = keys
        GlossService.shared.request(phrases: phrases, fallback: fallback, token: token) { [weak self] map in
            guard let self, self.keys == snapshotKeys, token == self.glossToken else { return }
            for (phrase, gloss) in map {
                self.applyGloss(phrase: phrase, gloss: gloss)
            }
            self.render(client: nil)
        }
    }

    private func applyGloss(phrase: String, gloss: String) {
        guard !gloss.isEmpty else { return }
        for i in candidates.indices where candidates[i].phrase == phrase {
            candidates[i].gloss = gloss
        }
    }

    private func commitIndex(_ index: Int, client: IMKTextInput?, insertRemainingRaw: Bool) {
        let visible = visibleCandidates()
        guard !visible.isEmpty else {
            insert(keys, client: client)
            clear(commit: false, client: client)
            return
        }
        let idx = min(max(index, 0), visible.count - 1)
        let chosen = visible[idx]
        insert(chosen.phrase, client: client)
        if chosen.consumed > 0, chosen.consumed < keys.count {
            keys = String(keys.dropFirst(chosen.consumed))
            selected = 0
            page = 0
            refresh(client: client)
        } else {
            clear(commit: false, client: client)
        }
        _ = insertRemainingRaw
    }

    private func clear(commit: Bool, client: IMKTextInput?) {
        if commit, !keys.isEmpty {
            insert(keys, client: client)
        }
        keys = ""
        candidates = []
        selected = 0
        page = 0
        mark("", client: client)
        CandidatePanel.shared.hide()
    }

    private func segmentedKeys() -> String {
        switch scheme {
        case .xiaohe:
            let (units, rest) = Xiaohe.chunk(keys)
            return Pinyin.formatSegmented(units, rest: rest)
        case .quanpin:
            let (units, rest) = Pinyin.segmentQuanpinPrefix(keys)
            return Pinyin.formatSegmented(units, rest: rest)
        }
    }

    private func mark(_ text: String, client: IMKTextInput?) {
        let range = NSRange(location: (text as NSString).length, length: 0)
        let replace = NSRange(location: NSNotFound, length: NSNotFound)
        client?.setMarkedText(text, selectionRange: range, replacementRange: replace)
    }

    private func insert(_ text: String, client: IMKTextInput?) {
        guard !text.isEmpty else { return }
        let replace = NSRange(location: NSNotFound, length: NSNotFound)
        client?.insertText(text, replacementRange: replace)
    }

    private func caretRect(client: IMKTextInput?) -> NSRect? {
        guard let client else { return nil }
        var rect = NSRect.zero
        _ = client.attributes(forCharacterIndex: 0, lineHeightRectangle: &rect)
        if rect.width > 0 || rect.height > 0 {
            return rect
        }
        return nil
    }
}

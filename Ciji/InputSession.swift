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
    private var shiftTapPending = false

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
        clear(client: nil)
        CandidatePanel.shared.hide()
        UserHistory.shared.resetContext()
    }

    func commitIfNeeded(client: IMKTextInput?) {
        if !keys.isEmpty {
            commitIndex(selected, client: client)
        }
    }

    func handle(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        if event.type == .flagsChanged {
            return handleFlags(event, client: client)
        }
        guard event.type == .keyDown else { return false }
        shiftTapPending = false

        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if mods.contains(.control), mods.contains(.shift), event.charactersIgnoringModifiers?.lowercased() == "p" {
            toggleScheme(client: client)
            return true
        }
        if mods.contains(.command) || mods.contains(.control) || mods.contains(.option) {
            if !keys.isEmpty {
                // Let shortcuts through, but don't leave a dangling composition.
                commitIndex(selected, client: client)
            }
            return false
        }

        if asciiMode {
            return false
        }

        let composing = !keys.isEmpty
        switch event.keyCode {
        case 53: // escape
            guard composing else { return false }
            clear(client: client)
            return true
        case 51: // delete
            guard composing else { return false }
            keys.removeLast()
            selected = 0
            page = 0
            refresh(client: client)
            return true
        case 36, 76: // return / keypad enter → raw letters
            guard composing else { return false }
            insert(keys.replacingOccurrences(of: "'", with: ""), client: client)
            clear(client: client)
            UserHistory.shared.resetContext()
            return true
        case 126: // up
            guard composing else { return false }
            moveSelection(-1, client: client)
            return true
        case 125: // down
            guard composing else { return false }
            moveSelection(1, client: client)
            return true
        case 116, 123: // page up, left
            guard composing else { return false }
            page(delta: -1, client: client)
            return true
        case 121, 124: // page down, right
            guard composing else { return false }
            page(delta: 1, client: client)
            return true
        case 48: // tab
            guard composing else { return false }
            if mods.contains(.shift) { page(delta: -1, client: client) } else { page(delta: 1, client: client) }
            return true
        default:
            break
        }

        let chars = event.charactersIgnoringModifiers ?? ""
        if composing {
            switch chars {
            case " ":
                commitIndex(selected, client: client)
                return true
            case "-", "[":
                page(delta: -1, client: client)
                return true
            case "=", "]":
                page(delta: 1, client: client)
                return true
            case "'" where scheme == .quanpin:
                if keys.last != "'" {
                    keys.append("'")
                    refresh(client: client)
                }
                return true
            default:
                break
            }
            if let number = Int(chars), (1...9).contains(number) {
                if number <= visibleCandidates().count {
                    commitIndex(number - 1, client: client)
                }
                return true
            }
        }

        if let first = chars.first, chars.count == 1, first.isASCII, first.isLetter {
            if mods.contains(.shift) && !composing {
                // Shift+letter with nothing composed types the capital directly.
                return false
            }
            keys.append(Character(first.lowercased()))
            selected = 0
            page = 0
            refresh(client: client)
            return true
        }

        let typed = event.characters ?? chars
        if let mapped = Self.punct[typed] ?? Self.punct[chars] {
            if composing {
                commitIndex(selected, client: client)
            }
            insert(mapped, client: client)
            UserHistory.shared.resetContext()
            return true
        }

        if composing, !typed.isEmpty {
            commitIndex(selected, client: client)
            insert(typed, client: client)
            UserHistory.shared.resetContext()
            return true
        }
        if !typed.isEmpty {
            UserHistory.shared.resetContext()
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
            clear(client: client)
        }
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    func toggleASCII(client: IMKTextInput?) {
        setASCII(!asciiMode, client: client)
    }

    private func handleFlags(_ event: NSEvent, client: IMKTextInput?) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if event.keyCode == 0x39 { // Caps Lock
            setASCII(mods.contains(.capsLock), client: client)
            return false
        }
        // A lone tap of Shift (56 left / 60 right) toggles 中/英.
        if event.keyCode == 56 || event.keyCode == 60 {
            if mods == .shift {
                shiftTapPending = true
            } else if mods.isEmpty, shiftTapPending {
                shiftTapPending = false
                if !keys.isEmpty {
                    insert(keys.replacingOccurrences(of: "'", with: ""), client: client)
                    clear(client: client)
                }
                setASCII(!asciiMode, client: client)
            } else {
                shiftTapPending = false
            }
            return false
        }
        shiftTapPending = false
        return false
    }

    private func moveSelection(_ delta: Int, client: IMKTextInput?) {
        let count = visibleCandidates().count
        guard count > 0 else { return }
        let next = selected + delta
        if next < 0 {
            if page > 0 {
                page -= 1
                selected = visibleCandidates().count - 1
            }
        } else if next >= count {
            if (page + 1) * pageSize < candidates.count {
                page += 1
                selected = 0
            }
        } else {
            selected = next
        }
        render(client: client)
        requestGlosses()
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
        requestGlosses()
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

    private func commitIndex(_ index: Int, client: IMKTextInput?) {
        let visible = visibleCandidates()
        guard !visible.isEmpty else {
            insert(keys.replacingOccurrences(of: "'", with: ""), client: client)
            clear(client: client)
            return
        }
        let idx = min(max(index, 0), visible.count - 1)
        let chosen = visible[idx]
        insert(chosen.phrase, client: client)
        UserHistory.shared.record(chosen)
        var remaining = chosen.consumed > 0 ? String(keys.dropFirst(chosen.consumed)) : ""
        while remaining.hasPrefix("'") { remaining.removeFirst() }
        if !remaining.isEmpty {
            keys = remaining
            selected = 0
            page = 0
            refresh(client: client)
        } else {
            clear(client: client)
        }
    }

    private func clear(client: IMKTextInput?) {
        keys = ""
        candidates = []
        selected = 0
        page = 0
        mark("", client: client)
        CandidatePanel.shared.hide()
    }

    private func segmentedKeys() -> String {
        Segmentation.make(scheme, keys: keys).display
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

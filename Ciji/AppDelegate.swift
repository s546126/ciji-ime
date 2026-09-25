import Cocoa
import InputMethodKit
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppConfig.ensureSupportFiles()
        _ = Lexicon.shared
        installStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "词"
        item.button?.toolTip = "词记 — 小鹤/全拼，候选英文释义"
        item.menu = makeMenu()
        statusItem = item
        NotificationCenter.default.addObserver(self, selector: #selector(rebuildMenu), name: .cijiStateChanged, object: nil)
    }

    @objc private func rebuildMenu() {
        statusItem?.menu = makeMenu()
        let session = SessionStore.shared.current()
        if session.isASCII {
            statusItem?.button?.title = "A"
        } else {
            statusItem?.button?.title = "词"
        }
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu(title: "词记")
        menu.autoenablesItems = false
        menu.delegate = self
        populate(menu)
        return menu
    }

    /// Rebuild on open so statuses (Jev, Relingo, 生词本) are current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        populate(menu)
    }

    private func populate(_ menu: NSMenu) {
        let session = SessionStore.shared.current()
        let scheme = session.currentScheme
        let config = AppConfig.load()

        @discardableResult
        func item(_ title: String, _ action: Selector?, state: Bool? = nil, enabled: Bool = true) -> NSMenuItem {
            let it = NSMenuItem(title: title, action: action, keyEquivalent: "")
            it.target = self
            it.isEnabled = enabled
            if let state { it.state = state ? .on : .off }
            menu.addItem(it)
            return it
        }

        item("小鹤双拼", #selector(selectXiaohe(_:)), state: scheme == .xiaohe)
        item("全拼", #selector(selectQuanpin(_:)), state: scheme == .quanpin)
        item("英文 ASCII（Shift / Caps Lock）", #selector(toggleASCII(_:)), state: session.isASCII)
        menu.addItem(.separator())

        item("Jev 智能重排", #selector(toggleJev(_:)), state: config.jev.enabled)
        item("    状态：\(JevService.shared.status)", nil, enabled: false)
        menu.addItem(.separator())

        let vocab = VocabBook.shared
        item("生词本（\(vocab.items.count) 个，待复习 \(vocab.dueItems.count)）…", #selector(openVocab(_:)))
        item("Relingo：立即同步", #selector(syncRelingo(_:)))
        item("    \(RelingoSync.shared.status)", nil, enabled: false)
        item("Relingo：导出英文单词表…", #selector(exportRelingo(_:)))
        item("Relingo：导入单词表…", #selector(importRelingo(_:)))
        menu.addItem(.separator())

        item("打开配置文件夹", #selector(openConfig(_:)))
        item("快捷键说明 / 关于词记", #selector(showAbout(_:)))
    }

    @objc func toggleJev(_ sender: Any?) {
        var cfg = AppConfig.load()
        cfg.jev.enabled.toggle()
        cfg.persist()
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func openVocab(_ sender: Any?) {
        NSWorkspace.shared.open(VocabBook.shared.exportCSV())
    }

    @objc func syncRelingo(_ sender: Any?) {
        RelingoSync.shared.pull(force: true) { _ in
            NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
        }
    }

    @objc func exportRelingo(_ sender: Any?) {
        NSWorkspace.shared.activateFileViewerSelecting([RelingoSync.shared.exportWordList(), VocabBook.shared.exportCSV()])
    }

    @objc func importRelingo(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .commaSeparatedText, .tabSeparatedText, .text]
        panel.allowsMultipleSelection = false
        panel.message = "选择 Relingo 导出的单词表（txt/csv，每行一个英文单词）"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let added = RelingoSync.shared.importFile(url)
        let alert = NSAlert()
        alert.messageText = "已导入 \(added) 个新单词"
        alert.informativeText = "候选里英文释义命中这些单词时会标「R」。"
        alert.runModal()
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func selectXiaohe(_ sender: Any?) {
        SessionStore.shared.current().setScheme(.xiaohe, client: nil)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func selectQuanpin(_ sender: Any?) {
        SessionStore.shared.current().setScheme(.quanpin, client: nil)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func toggleASCII(_ sender: Any?) {
        SessionStore.shared.current().toggleASCII(client: nil)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func openConfig(_ sender: Any?) {
        AppConfig.ensureSupportFiles()
        NSWorkspace.shared.open(AppConfig.supportDirectory())
    }

    @objc func showAbout(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "词记"
        alert.informativeText = """
        边打中文边背单词：每个候选都带英文释义。

        Shift 单击：中/英　Ctrl+Shift+P：小鹤/全拼
        空格 上屏　1–9 选择　↑↓ 高亮　-/=、Tab 翻页　回车 上屏字母
        输入英文（如 hello）也能出中文候选

        组字时：
        Ctrl+S  加入/移出生词本（同步 Relingo）
        Ctrl+R  朗读英文
        Ctrl+T  整句翻译（再按一次上屏英文）
        Ctrl+`  立即让 Jev 重排

        ✦ Jev 推荐　★ 生词本　复习 今天该复习　R 你的 Relingo 生词
        配置：~/Library/Application Support/Ciji/config.json
        """
        alert.runModal()
    }
}

extension Notification.Name {
    static let cijiStateChanged = Notification.Name("com.shengtao.ciji.stateChanged")
}

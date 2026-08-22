import Cocoa
import InputMethodKit

final class AppDelegate: NSObject, NSApplicationDelegate {
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
        let session = SessionStore.shared.active
        if session?.isASCII == true {
            statusItem?.button?.title = "A"
        } else {
            statusItem?.button?.title = "词"
        }
    }

    private func makeMenu() -> NSMenu {
        let session = SessionStore.shared.active
        let scheme = session?.currentScheme ?? AppConfig.load().preferredScheme
        let menu = NSMenu(title: "词记")
        let xiaohe = NSMenuItem(title: "小鹤双拼", action: #selector(selectXiaohe(_:)), keyEquivalent: "p")
        xiaohe.keyEquivalentModifierMask = [.control, .shift]
        xiaohe.state = scheme == .xiaohe ? .on : .off
        let quanpin = NSMenuItem(title: "全拼", action: #selector(selectQuanpin(_:)), keyEquivalent: "")
        quanpin.state = scheme == .quanpin ? .on : .off
        let ascii = NSMenuItem(title: "英文 ASCII（Caps Lock）", action: #selector(toggleASCII(_:)), keyEquivalent: "")
        ascii.state = session?.isASCII == true ? .on : .off
        menu.addItem(xiaohe)
        menu.addItem(quanpin)
        menu.addItem(ascii)
        menu.addItem(.separator())
        menu.addItem(withTitle: "打开配置文件夹", action: #selector(openConfig(_:)), keyEquivalent: ",")
        menu.addItem(.separator())
        menu.addItem(withTitle: "关于词记", action: #selector(showAbout(_:)), keyEquivalent: "")
        return menu
    }

    @objc func selectXiaohe(_ sender: Any?) {
        SessionStore.shared.active?.setScheme(.xiaohe, client: nil)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func selectQuanpin(_ sender: Any?) {
        SessionStore.shared.active?.setScheme(.quanpin, client: nil)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func toggleASCII(_ sender: Any?) {
        SessionStore.shared.active?.toggleASCII(client: nil)
        NotificationCenter.default.post(name: .cijiStateChanged, object: nil)
    }

    @objc func openConfig(_ sender: Any?) {
        AppConfig.ensureSupportFiles()
        NSWorkspace.shared.open(AppConfig.supportDirectory())
    }

    @objc func showAbout(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "词记"
        alert.informativeText = "macOS 中文输入法。默认小鹤双拼，候选栏显示英文释义。\n配置：~/Library/Application Support/Ciji/config.json\nCtrl+Shift+P 切换小鹤/全拼。"
        alert.runModal()
    }
}

extension Notification.Name {
    static let cijiStateChanged = Notification.Name("com.shengtao.ciji.stateChanged")
}

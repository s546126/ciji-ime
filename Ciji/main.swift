import Cocoa
import InputMethodKit

/// IMKServer must outlive `NSApp.run()`.
private var imkServer: IMKServer?

private func start() {
    let identifier = Bundle.main.bundleIdentifier ?? "com.shengtao.ciji.inputmethod"
    let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
        ?? "\(identifier)_Connection"
    imkServer = IMKServer(name: connectionName, bundleIdentifier: identifier)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}

start()

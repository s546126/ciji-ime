import Cocoa
import InputMethodKit

/// IMKServer and AppDelegate must outlive `NSApp.run()`.
/// NSApplication.delegate is weak; without a strong keep-alive the status
/// menu target disappears and clicks do nothing.
private var imkServer: IMKServer?
private var appDelegate: AppDelegate?

private func start() {
    let identifier = Bundle.main.bundleIdentifier ?? "com.shengtao.ciji.inputmethod"
    let connectionName = (Bundle.main.object(forInfoDictionaryKey: "InputMethodConnectionName") as? String)
        ?? "\(identifier)_Connection"
    imkServer = IMKServer(name: connectionName, bundleIdentifier: identifier)
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    let delegate = AppDelegate()
    appDelegate = delegate
    app.delegate = delegate
    app.run()
}

start()

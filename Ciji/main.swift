import Carbon
import Cocoa
import InputMethodKit

/// IMKServer and AppDelegate must outlive `NSApp.run()`.
/// NSApplication.delegate is weak; without a strong keep-alive the status
/// menu target disappears and clicks do nothing.
private var imkServer: IMKServer?
private var appDelegate: AppDelegate?

/// `Ciji --register`: register this bundle with Text Input Sources and enable it,
/// so it shows up without logging out. Used by the DMG installer.
private func registerAndEnable() -> Int32 {
    let url = Bundle.main.bundleURL as CFURL
    let status = TISRegisterInputSource(url)
    guard let identifier = Bundle.main.bundleIdentifier else { return 1 }
    let filter = [kTISPropertyBundleID as String: identifier] as CFDictionary
    var enabled = 0
    if let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] {
        for source in list {
            if TISEnableInputSource(source) == 0 { enabled += 1 }
        }
    }
    print("Ciji: TISRegisterInputSource=\(status), enabled \(enabled) input source(s)")
    return status == 0 ? 0 : 1
}

private func start() {
    if CommandLine.arguments.contains("--register") {
        exit(registerAndEnable())
    }
    if CommandLine.arguments.contains("--selftest") {
        exit(SelfTest.run())
    }
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

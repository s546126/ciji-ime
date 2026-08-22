import Cocoa
import InputMethodKit

/// Thin IMK facade. Session state is stored off the controller so Caps Lock
/// IME bouncing does not pin large graphs to a short-lived controller.
@objc(CijiInputController)
final class CijiInputController: IMKInputController {
    private func session(for client: Any?) -> InputSession {
        SessionStore.shared.session(for: client ?? self.client())
    }

    private func textClient(_ sender: Any?) -> IMKTextInput? {
        (sender as? IMKTextInput) ?? (client() as? IMKTextInput)
    }

    override func recognizedEvents(_ sender: Any!) -> Int {
        Int(NSEvent.EventTypeMask.keyDown.rawValue | NSEvent.EventTypeMask.flagsChanged.rawValue)
    }

    override func handle(_ event: NSEvent!, client sender: Any!) -> Bool {
        guard let event else { return false }
        return session(for: sender).handle(event, client: textClient(sender))
    }

    override func activateServer(_ sender: Any!) {
        super.activateServer(sender)
        let current = session(for: sender)
        SessionStore.shared.active = current
        current.activate()
    }

    override func deactivateServer(_ sender: Any!) {
        session(for: sender).deactivate()
        super.deactivateServer(sender)
    }

    override func commitComposition(_ sender: Any!) {
        session(for: sender).commitIfNeeded(client: textClient(sender))
    }

    override func menu() -> NSMenu! {
        session(for: client()).menu()
    }
}

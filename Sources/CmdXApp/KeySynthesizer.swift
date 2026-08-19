import CoreGraphics

/// Posts the keystrokes Finder already understands. Every synthetic event carries
/// a sentinel so the tap recognises its own output — without it the synthetic
/// Cmd+C re-enters the tap and recurses forever.
@MainActor
final class KeySynthesizer {
    static let sentinel: Int64 = 0x436D_6458  // "CmdX" in ASCII

    private let keyC: CGKeyCode = 8
    private let keyV: CGKeyCode = 9

    func sendCopy() {
        post(keyCode: keyC, flags: .maskCommand)
    }

    /// Finder's "Move Item Here" — the native command CmdX rebinds Cmd+V onto.
    func sendMoveHere() {
        post(keyCode: keyV, flags: [.maskCommand, .maskAlternate])
    }

    private func post(keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        for isDown in [true, false] {
            guard let event = CGEvent(
                keyboardEventSource: source, virtualKey: keyCode, keyDown: isDown)
            else { continue }
            event.flags = flags
            event.setIntegerValueField(.eventSourceUserData, value: Self.sentinel)
            event.post(tap: .cgSessionEventTap)
        }
    }
}

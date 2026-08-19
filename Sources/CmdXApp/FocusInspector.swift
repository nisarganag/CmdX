import ApplicationServices
import Foundation

/// Answers "does Finder currently have a text field focused?" — the check that
/// keeps Cmd+X cutting text while renaming a file instead of cutting the file.
@MainActor
final class FocusInspector {
    /// Genuine AX roles (`kAXRoleAttribute` values) known to be text inputs.
    /// Finder's exact rename-field role was not verified, so this alone is not
    /// trusted — see the subrole and settable-value fallbacks below.
    private static let textFieldRoles: Set<String> = [
        kAXTextFieldRole as String,
        kAXTextAreaRole as String,
        kAXComboBoxRole as String,
    ]

    /// Queried live on every intercepted keystroke rather than cached: focus
    /// changes inside Finder without any app activation — clicking into a rename
    /// field is the common case — so a cache would routinely answer stale.
    ///
    /// Returns true on any failure. Failing toward "text field focused" means a
    /// broken query degrades to stock macOS behaviour rather than eating a
    /// keystroke.
    func isTextFieldFocused(pid: pid_t) -> Bool {
        guard pid > 0 else {
            return true
        }

        let app = AXUIElementCreateApplication(pid)
        // Bound the tap callback against an unresponsive Finder. A tap that takes
        // too long is disabled by the system.
        AXUIElementSetMessagingTimeout(app, 0.05)

        var focusedValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
                  app, kAXFocusedUIElementAttribute as CFString, &focusedValue) == .success,
              let focused = focusedValue,
              CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            return true
        }

        let element = focused as! AXUIElement

        var roleValue: CFTypeRef?
        let roleRead = AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleValue) == .success
        let role = roleRead ? (roleValue as? String) : nil

        if let role, Self.textFieldRoles.contains(role) {
            return true
        }

        // The role allowlist above is not exhaustive (e.g. a search field
        // reports its role as a plain text field with a subrole, not a role of
        // its own), so fall back to the subrole before giving up on role-based
        // matching entirely.
        var subroleValue: CFTypeRef?
        let subroleRead = AXUIElementCopyAttributeValue(
            element, kAXSubroleAttribute as CFString, &subroleValue) == .success
        let subrole = subroleRead ? (subroleValue as? String) : nil

        if let subrole, subrole == (kAXSearchFieldSubrole as String) {
            return true
        }

        // Editability fallback: a settable value is what actually makes something
        // a text input, independent of how Finder labels its role/subrole. This
        // does not depend on enumerating every role/subrole Finder might use.
        // Biased toward over-triggering deliberately: if this over-triggers,
        // CmdX simply stops intercepting in Finder (visible, harmless, caught
        // immediately by testing); if it under-triggers, a file gets moved
        // during a rename, which is the worst failure this app can have.
        var settable: DarwinBoolean = false
        let settableRead = AXUIElementIsAttributeSettable(
            element, kAXValueAttribute as CFString, &settable) == .success

        guard settableRead else {
            return true
        }

        let isSettable = settable.boolValue
        return isSettable
    }
}

/// Decides whether a key-down carrying a given set of modifiers is one CmdX
/// should act on at all.
///
/// This lives in `CmdXCore` rather than beside the event tap so it can be
/// tested. It guards the most consequential rule in the app: `Cmd+Option+Delete`
/// is macOS's *permanent* delete, with no Trash and no undo, and CmdX must never
/// intercept or reinterpret it.
public enum ModifierGate {
    public struct Modifiers: Sendable, Hashable {
        public let command: Bool
        public let option: Bool
        public let shift: Bool
        public let control: Bool
        public let fn: Bool

        public init(
            command: Bool = false,
            option: Bool = false,
            shift: Bool = false,
            control: Bool = false,
            fn: Bool = false
        ) {
            self.command = command
            self.option = option
            self.shift = shift
            self.control = control
            self.fn = fn
        }
    }

    /// True only for the exact combination each key is bound to.
    ///
    /// Cut and paste ride on Command alone, so `Cmd+Option+V` (Finder's own
    /// "Move Item Here") and `Cmd+Shift+V` stay untouched. Delete is the inverse:
    /// a naked keystroke, so every modified form — including `Cmd+Delete`,
    /// `Option+Delete` and the irreversible `Cmd+Option+Delete` — passes straight
    /// through to macOS.
    public static func shouldConsider(key: Key, modifiers: Modifiers) -> Bool {
        let hasOther = modifiers.option || modifiers.shift || modifiers.control

        if key.requiresCommand {
            return modifiers.command && !hasOther
        }
        // fn is excluded too: a keyboard that reports fn+Delete as this keycode
        // must still forward-delete rather than trash a file.
        return !modifiers.command && !hasOther && !modifiers.fn
    }
}

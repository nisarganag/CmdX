/// The only two keys CmdX ever intercepts.
public enum Key: Sendable, Hashable {
    case x
    case v

    /// Maps a CoreGraphics virtual keycode. Returns nil for every other key.
    public init?(virtualKeyCode: Int64) {
        switch virtualKeyCode {
        case 7: self = .x
        case 9: self = .v
        default: return nil
        }
    }
}

public enum Phase: Sendable, Hashable {
    case down
    case up
}

/// What the event tap should do with an intercepted event.
public enum Decision: Sendable, Hashable {
    /// Hand the event to the system unchanged.
    case passThrough
    /// Discard the event and synthesize Cmd+C in its place.
    case swallowAndCopy
    /// Discard the event and synthesize Cmd+Option+V in its place.
    case swallowAndMove
    /// Discard the event and synthesize nothing (a matching key release).
    case swallow
}

public enum CutState: Sendable, Hashable {
    case idle
    /// Cmd+C synthesized; waiting to see whether the pasteboard advanced.
    case arming(preCount: Int)
    /// A cut is live and valid for the recorded pasteboard change count.
    case armed(count: Int)
}

/// Everything the state machine needs in order to decide. The defaults describe
/// the common case — enabled, Finder frontmost, file list focused — so that test
/// cases only have to state what differs.
public struct Input: Sendable, Hashable {
    public let key: Key
    public let phase: Phase
    public let isEnabled: Bool
    public let isFinderFrontmost: Bool
    public let isTextFieldFocused: Bool
    public let pasteboardChangeCount: Int
    public let isAutorepeat: Bool

    public init(
        key: Key,
        phase: Phase,
        isEnabled: Bool = true,
        isFinderFrontmost: Bool = true,
        isTextFieldFocused: Bool = false,
        pasteboardChangeCount: Int = 0,
        isAutorepeat: Bool = false
    ) {
        self.key = key
        self.phase = phase
        self.isEnabled = isEnabled
        self.isFinderFrontmost = isFinderFrontmost
        self.isTextFieldFocused = isTextFieldFocused
        self.pasteboardChangeCount = pasteboardChangeCount
        self.isAutorepeat = isAutorepeat
    }
}

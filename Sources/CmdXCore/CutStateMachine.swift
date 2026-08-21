/// The complete interception policy for CmdX.
///
/// Pure and synchronous: it performs no I/O and touches no system API, so every
/// behaviour is exercised by unit tests without a live event tap. `@MainActor`
/// because the event tap is attached to the main run loop.
@MainActor
public final class CutStateMachine {
    public private(set) var state: CutState = .idle

    /// Keys whose press was swallowed, so the matching release can be swallowed
    /// too. Without this Finder receives an orphaned key release.
    private var swallowedDowns: Set<Key> = []

    public init() {}

    public func handle(_ input: Input) -> Decision {
        // Rule 8 — a key release is judged solely by whether its press was
        // swallowed. Deliberately ahead of the gating rule: if the user releases
        // the key after Finder has lost focus, the release must still be eaten.
        if input.phase == .up {
            return swallowedDowns.remove(input.key) != nil ? .swallow : .passThrough
        }

        // An auto-repeat press is a continuation of a press already judged, not a
        // new intent. Repeat what was decided for the original: keep swallowing a
        // swallowed key so Finder never sees a raw repeat, and never re-arm or
        // re-paste on a tick the user did not deliberately make.
        if input.isAutorepeat {
            return swallowedDowns.contains(input.key) ? .swallow : .passThrough
        }

        // Rule 1 — gating. Checked first and unconditionally.
        // Rule 11 — each key is gated by its own feature, so cut/paste and
        // trash can be switched on independently of each other.
        guard input.enabledFeatures.contains(input.key.feature),
              input.isFinderFrontmost,
              !input.isTextFieldFocused
        else {
            return .passThrough
        }

        switch input.key {
        case .delete:
            // Rule 10 — a bare Delete on the file list becomes Cmd+Delete, so
            // Finder moves the selection to the Trash. Stateless on purpose: it
            // must not disturb a pending cut, since deleting one file has no
            // bearing on a different file already cut.
            swallowedDowns.insert(.delete)
            return .swallowAndTrash

        case .x:
            // Rule 2 — swallow, synthesize Cmd+C, and wait for the pasteboard.
            state = .arming(preCount: input.pasteboardChangeCount)
            swallowedDowns.insert(.x)
            return .swallowAndCopy

        case .v:
            switch state {
            case .idle:
                // Rule 7 — no cut pending, so this is an ordinary paste.
                return .passThrough

            case .arming(let preCount):
                // The user pasted before the synthetic Cmd+C settled. preCount was
                // recorded at cut time, so we can still tell whether the copy landed.
                state = .idle
                guard input.pasteboardChangeCount > preCount else {
                    // It has not landed: the pasteboard still holds older content, and
                    // moving that would relocate a file the user never cut. Degrade to
                    // an ordinary paste, which is at worst a recoverable copy.
                    return .passThrough
                }
                swallowedDowns.insert(.v)
                return .swallowAndMove

            case .armed(let count):
                state = .idle
                guard input.pasteboardChangeCount == count else {
                    // Rule 5 — something was copied after the cut, so the cut is
                    // stale and this is an ordinary paste.
                    return .passThrough
                }
                // Rule 4 — the cut is still valid: move.
                swallowedDowns.insert(.v)
                return .swallowAndMove
            }
        }
    }

    /// Rule 3 — called shortly after a synthetic Cmd+C. The pasteboard advancing
    /// is the only reliable evidence that Finder actually copied a selection.
    public func resolveArming(currentChangeCount: Int) {
        guard case .arming(let preCount) = state else { return }
        state = currentChangeCount > preCount ? .armed(count: currentChangeCount) : .idle
    }

    /// Drops any pending cut. Used when CmdX is disabled or loses its event tap.
    public func invalidate() {
        state = .idle
    }

    /// Drives the menu bar icon: true from the moment Cmd+X is pressed until the
    /// cut is either pasted or invalidated.
    public var isArmed: Bool {
        switch state {
        case .idle: return false
        case .arming, .armed: return true
        }
    }
}

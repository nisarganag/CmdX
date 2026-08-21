import AppKit
import CmdXCore
import CoreGraphics

@MainActor
final class EventTapService {
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    private let machine = CutStateMachine()
    private let synthesizer = KeySynthesizer()
    private let frontmost: FrontmostWatcher
    private let focus: FocusInspector

    /// Fires whenever a cut is armed or cleared, so the icon can follow.
    var onArmedChange: ((Bool) -> Void)?

    var enabledFeatures: Set<Feature> = Set(Feature.allCases) {
        didSet {
            // Dropping cut/paste must clear a pending cut. Otherwise switching it
            // back on later would resurrect an arm whose pasteboard has moved on.
            guard !enabledFeatures.contains(.cutPaste) else { return }
            machine.invalidate()
            onArmedChange?(false)
        }
    }

    var isRunning: Bool { tap != nil }

    init(frontmost: FrontmostWatcher, focus: FocusInspector) {
        self.frontmost = frontmost
        self.focus = focus
    }

    /// Returns false when Accessibility permission is missing — tapCreate is the
    /// authoritative check, since it is the call that actually needs the grant.
    @discardableResult
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.keyUp.rawValue)

        // The tap deliberately keeps this service alive for as long as it is
        // installed — stop() is what breaks the retain by releasing it below.
        let selfPtr = Unmanaged.passRetained(self).toOpaque()
        guard let port = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let service = Unmanaged<EventTapService>
                    .fromOpaque(refcon).takeUnretainedValue()
                // Valid: the tap is attached to the main run loop. The isolated
                // closure returns Bool rather than the CGEvent itself — Bool is
                // Sendable, so this crosses the actor boundary without needing
                // CGEvent (or any other CoreGraphics type) to be Sendable, and
                // without silencing concurrency checking for the whole file.
                let shouldSwallow = MainActor.assumeIsolated {
                    service.handle(type: type, event: event)
                }
                return shouldSwallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            // tapCreate failed (typically Accessibility not granted): balance the retain
            // we took above, or every failed start leaks one.
            Unmanaged<EventTapService>.fromOpaque(selfPtr).release()
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: port, enable: true)

        tap = port
        runLoopSource = source
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            // Balances the passRetained(self) in start(). This sits inside the
            // same `if let tap` guard that start() uses to prevent a double
            // retain, so calling stop() twice (tap is already nil the second
            // time) cannot release twice.
            Unmanaged<EventTapService>.passUnretained(self).release()
        }
        runLoopSource = nil
        tap = nil
        machine.invalidate()
        onArmedChange?(false)
    }

    /// Decides the fate of one intercepted event. Returns `true` to swallow the
    /// event — Finder never sees it — or `false` to pass it through unchanged.
    /// The sense is deliberately named `shouldSwallow` at the call site so a
    /// later edit cannot invert it by accident.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // macOS disables a tap that responds too slowly. Re-enable it, or CmdX
        // stops working silently after the first hiccup.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        // Never let our own synthetic events reach the state machine.
        guard event.getIntegerValueField(.eventSourceUserData) != KeySynthesizer.sentinel
        else { return false }

        let phase: Phase
        switch type {
        case .keyDown: phase = .down
        case .keyUp: phase = .up
        default: return false
        }

        guard let key = Key(virtualKeyCode:
                event.getIntegerValueField(.keyboardEventKeycode))
        else { return false }

        // Command alone — but only gates the down-stroke. Leaving Cmd+Option+V
        // and Cmd+Shift+V untouched means Finder's own "Move Item Here" and
        // paste-and-match-style keep working. A keyUp must reach the state
        // machine even without Command held: if the user releases Cmd before X,
        // the X keyUp carries no Command flag, yet rule 8 still needs it to clear
        // the stale swallowedDowns entry — otherwise a later Cmd+X anywhere gets
        // wrongly swallowed. A bare keyUp with nothing recorded is harmless: the
        // state machine just returns .passThrough for it.
        if phase == .down {
            let flags = event.flags
            // Delegated to CmdXCore so the rule is unit-tested. It is the guard
            // that keeps CmdX away from Cmd+Option+Delete, which deletes
            // permanently with no Trash and no undo.
            guard ModifierGate.shouldConsider(key: key, modifiers: .init(
                command: flags.contains(.maskCommand),
                option: flags.contains(.maskAlternate),
                shift: flags.contains(.maskShift),
                control: flags.contains(.maskControl),
                fn: flags.contains(.maskSecondaryFn)
            )) else { return false }
        }

        let inFinder = frontmost.isFinderFrontmost
        let input = Input(
            key: key,
            phase: phase,
            enabledFeatures: enabledFeatures,
            isFinderFrontmost: inFinder,
            isTextFieldFocused: inFinder
                ? focus.isTextFieldFocused(pid: frontmost.finderPID)
                : false,
            pasteboardChangeCount: NSPasteboard.general.changeCount,
            // Rule 9. Without this the state machine cannot tell a held key from a
            // deliberate second press, and a held Cmd+V leaks a raw paste to Finder.
            isAutorepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        )

        let decision = machine.handle(input)

        switch decision {
        case .passThrough:
            onArmedChange?(machine.isArmed)
            return false

        case .swallow:
            onArmedChange?(machine.isArmed)
            return true

        case .swallowAndCopy:
            synthesizer.sendCopy()
            scheduleArmingResolution()
            onArmedChange?(machine.isArmed)
            return true

        case .swallowAndTrash:
            synthesizer.sendMoveToTrash()
            onArmedChange?(machine.isArmed)
            return true

        case .swallowAndMove:
            synthesizer.sendMoveHere()
            onArmedChange?(machine.isArmed)
            return true
        }
    }

    /// Finder updates the pasteboard asynchronously after receiving the synthetic
    /// Cmd+C, so the change count can only be read a beat later.
    private func scheduleArmingResolution() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.machine.resolveArming(
                    currentChangeCount: NSPasteboard.general.changeCount)
                self.onArmedChange?(self.machine.isArmed)
            }
        }
    }
}

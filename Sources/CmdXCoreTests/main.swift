import CmdXCore

@MainActor
func run() {
    let t = Harness()

    t.section("Gating — rule 1")

    t.equal("disabled passes Cmd+X through",
            CutStateMachine().handle(Input(key: .x, phase: .down, isEnabled: false)),
            .passThrough)

    let disabledPaste = CutStateMachine()
    _ = disabledPaste.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    disabledPaste.resolveArming(currentChangeCount: 11)
    t.equal("disabled passes Cmd+V through even with a cut armed",
            disabledPaste.handle(Input(key: .v, phase: .down, isEnabled: false, pasteboardChangeCount: 11)),
            .passThrough)

    t.equal("non-Finder app passes Cmd+X through",
            CutStateMachine().handle(Input(key: .x, phase: .down, isFinderFrontmost: false)),
            .passThrough)

    t.equal("text field focused passes Cmd+X through (rename cuts text)",
            CutStateMachine().handle(Input(key: .x, phase: .down, isTextFieldFocused: true)),
            .passThrough)

    let textFieldPaste = CutStateMachine()
    _ = textFieldPaste.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    textFieldPaste.resolveArming(currentChangeCount: 11)
    t.equal("text field focused passes Cmd+V through even with a cut armed (rename pastes text)",
            textFieldPaste.handle(Input(key: .v, phase: .down, isTextFieldFocused: true, pasteboardChangeCount: 11)),
            .passThrough)

    t.section("Keycode mapping")

    t.check("keycode 7 is X", Key(virtualKeyCode: 7) == .x)
    t.check("keycode 9 is V", Key(virtualKeyCode: 9) == .v)
    t.check("keycode 8 (C) is not mapped", Key(virtualKeyCode: 8) == nil)
    t.check("keycode 0 (A) is not mapped", Key(virtualKeyCode: 0) == nil)

    t.section("Arming — rules 2 and 3")

    let arming = CutStateMachine()
    t.equal("Cmd+X is swallowed and becomes a copy",
            arming.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10)),
            .swallowAndCopy)
    t.equal("Cmd+X records the pre-copy change count",
            arming.state,
            .arming(preCount: 10))
    t.check("machine reports armed while still arming", arming.isArmed)

    let selected = CutStateMachine()
    _ = selected.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    selected.resolveArming(currentChangeCount: 11)
    t.equal("pasteboard advanced means the cut is live",
            selected.state,
            .armed(count: 11))
    t.check("armed machine reports armed", selected.isArmed)

    let empty = CutStateMachine()
    _ = empty.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    empty.resolveArming(currentChangeCount: 10)
    t.equal("Cmd+X with nothing selected does not arm",
            empty.state,
            .idle)
    t.check("unarmed machine reports not armed", !empty.isArmed)

    let stray = CutStateMachine()
    stray.resolveArming(currentChangeCount: 99)
    t.equal("resolveArming while idle is a no-op", stray.state, .idle)

    let invalidated = CutStateMachine()
    _ = invalidated.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    invalidated.resolveArming(currentChangeCount: 11)
    invalidated.invalidate()
    t.equal("invalidate clears an armed cut", invalidated.state, .idle)

    t.section("Pasting — rules 4 through 7")

    let moving = CutStateMachine()
    _ = moving.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    moving.resolveArming(currentChangeCount: 11)
    t.equal("Cmd+V with a valid cut becomes a move",
            moving.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 11)),
            .swallowAndMove)
    t.equal("a completed move disarms", moving.state, .idle)

    let stale = CutStateMachine()
    _ = stale.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    stale.resolveArming(currentChangeCount: 11)
    t.equal("Cmd+V after copying something else is an ordinary paste",
            stale.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 12)),
            .passThrough)
    t.equal("a stale cut disarms", stale.state, .idle)

    let idlePaste = CutStateMachine()
    t.equal("Cmd+V with no cut pending is an ordinary paste",
            idlePaste.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 5)),
            .passThrough)

    let racing = CutStateMachine()
    _ = racing.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    t.equal("Cmd+V inside the arming window still moves",
            racing.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 11)),
            .swallowAndMove)
    t.equal("a move from the arming window disarms", racing.state, .idle)

    let unlandedRace = CutStateMachine()
    _ = unlandedRace.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    t.equal("Cmd+V inside the arming window before the copy lands is an ordinary paste",
            unlandedRace.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 10)),
            .passThrough)
    t.equal("a degraded paste from the arming window still disarms", unlandedRace.state, .idle)

    t.section("Key releases — rule 8")

    let releases = CutStateMachine()
    _ = releases.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    t.equal("release of a swallowed Cmd+X is swallowed",
            releases.handle(Input(key: .x, phase: .up, pasteboardChangeCount: 10)),
            .swallow)
    t.equal("the same release is only swallowed once",
            releases.handle(Input(key: .x, phase: .up, pasteboardChangeCount: 10)),
            .passThrough)

    let passedThrough = CutStateMachine()
    _ = passedThrough.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 5))
    t.equal("release of a passed-through Cmd+V also passes through",
            passedThrough.handle(Input(key: .v, phase: .up, pasteboardChangeCount: 5)),
            .passThrough)

    let leaving = CutStateMachine()
    _ = leaving.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    t.equal("release is swallowed even after Finder loses focus",
            leaving.handle(Input(key: .x, phase: .up, isFinderFrontmost: false)),
            .swallow)

    // Finding 3: EventTapService used to gate keyUp on the Command modifier too,
    // so releasing Cmd before X meant the X keyUp never reached this machine at
    // all, leaving .x stuck in swallowedDowns forever. The fix lets any keyUp for
    // a mapped key reach `handle` regardless of modifiers. At this layer that
    // just means rule 8 must still fire and clear the entry no matter what else
    // is going on around it — modeled here as the keyUp arriving after Finder is
    // no longer even relevant, since the machine never looked at modifier flags
    // to begin with.
    let cmdReleasedBeforeX = CutStateMachine()
    _ = cmdReleasedBeforeX.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    t.equal("X keyUp arriving after Cmd was already released still swallows and clears the stale entry",
            cmdReleasedBeforeX.handle(Input(key: .x, phase: .up, pasteboardChangeCount: 10)),
            .swallow)
    t.equal("a later X keyUp with nothing recorded passes through harmlessly",
            cmdReleasedBeforeX.handle(Input(key: .x, phase: .up, pasteboardChangeCount: 10)),
            .passThrough)

    t.section("Auto-repeat handling")

    let autoRepeatX = CutStateMachine()
    _ = autoRepeatX.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    t.equal("auto-repeat Cmd+X after a swallowed press is swallowed, not a new copy",
            autoRepeatX.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 30, isAutorepeat: true)),
            .swallow)
    t.equal("auto-repeat Cmd+X does not re-arm to the repeat's change count",
            autoRepeatX.state,
            .arming(preCount: 10))

    let autoRepeatV = CutStateMachine()
    _ = autoRepeatV.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    autoRepeatV.resolveArming(currentChangeCount: 11)
    _ = autoRepeatV.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 11))
    t.equal("auto-repeat Cmd+V after a swallowed move is swallowed, not a stray paste",
            autoRepeatV.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 11, isAutorepeat: true)),
            .swallow)

    let autoRepeatNeverSwallowed = CutStateMachine()
    t.equal("auto-repeat of a key that was never swallowed passes through",
            autoRepeatNeverSwallowed.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 5, isAutorepeat: true)),
            .passThrough)

    t.section("End-to-end sequences")

    let flow = CutStateMachine()
    t.equal("cut",
            flow.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 1)),
            .swallowAndCopy)
    _ = flow.handle(Input(key: .x, phase: .up, pasteboardChangeCount: 1))
    flow.resolveArming(currentChangeCount: 2)
    t.equal("paste moves",
            flow.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 2)),
            .swallowAndMove)
    _ = flow.handle(Input(key: .v, phase: .up, pasteboardChangeCount: 2))
    t.equal("a second paste no longer moves",
            flow.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 2)),
            .passThrough)

    t.finish()
}

run()

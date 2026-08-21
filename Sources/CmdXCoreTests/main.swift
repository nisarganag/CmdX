import CmdXCore

@MainActor
func run() {
    let t = Harness()

    t.section("Gating — rule 1")

    t.equal("disabled passes Cmd+X through",
            CutStateMachine().handle(Input(key: .x, phase: .down, enabledFeatures: [])),
            .passThrough)

    let disabledPaste = CutStateMachine()
    _ = disabledPaste.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    disabledPaste.resolveArming(currentChangeCount: 11)
    t.equal("disabled passes Cmd+V through even with a cut armed",
            disabledPaste.handle(Input(key: .v, phase: .down, enabledFeatures: [], pasteboardChangeCount: 11)),
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


    t.section("Delete key — rule 10 (move to Trash)")

    t.check("keycode 51 is delete", Key(virtualKeyCode: 51) == .delete)
    t.check("keycode 117 (forward delete) is NOT mapped", Key(virtualKeyCode: 117) == nil)

    t.equal("bare Delete on the file list trashes",
            CutStateMachine().handle(Input(key: .delete, phase: .down)),
            .swallowAndTrash)

    t.equal("Delete while renaming deletes text, not the file",
            CutStateMachine().handle(Input(key: .delete, phase: .down, isTextFieldFocused: true)),
            .passThrough)

    t.equal("Delete outside Finder is untouched",
            CutStateMachine().handle(Input(key: .delete, phase: .down, isFinderFrontmost: false)),
            .passThrough)

    t.equal("Delete while CmdX is disabled is untouched",
            CutStateMachine().handle(Input(key: .delete, phase: .down, enabledFeatures: [])),
            .passThrough)

    // Finder selects the next file after trashing one, so a repeating Delete
    // would walk down a folder trashing everything in it.
    let heldDelete = CutStateMachine()
    t.equal("first Delete press trashes",
            heldDelete.handle(Input(key: .delete, phase: .down)),
            .swallowAndTrash)
    t.equal("auto-repeat of a held Delete does NOT trash again",
            heldDelete.handle(Input(key: .delete, phase: .down, isAutorepeat: true)),
            .swallow)
    t.equal("release of a swallowed Delete is swallowed",
            heldDelete.handle(Input(key: .delete, phase: .up)),
            .swallow)

    // Delete is stateless: it must not disturb a pending cut.
    let cutThenDelete = CutStateMachine()
    _ = cutThenDelete.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    cutThenDelete.resolveArming(currentChangeCount: 11)
    t.equal("Delete still trashes while a cut is pending",
            cutThenDelete.handle(Input(key: .delete, phase: .down, pasteboardChangeCount: 11)),
            .swallowAndTrash)
    t.equal("deleting another file leaves a pending cut armed",
            cutThenDelete.state,
            .armed(count: 11))
    t.equal("the cut still pastes as a move afterwards",
            cutThenDelete.handle(Input(key: .v, phase: .down, pasteboardChangeCount: 11)),
            .swallowAndMove)


    t.section("Independent feature toggles — rule 11")

    t.equal("cut/paste is the cutPaste feature", Key.x.feature, .cutPaste)
    t.equal("paste is the cutPaste feature", Key.v.feature, .cutPaste)
    t.equal("delete is the trash feature", Key.delete.feature, .trash)

    // Trash off, cut/paste on — the common "I want cut but Delete scares me" case.
    t.equal("Delete passes through when only cut/paste is enabled",
            CutStateMachine().handle(Input(key: .delete, phase: .down, enabledFeatures: [.cutPaste])),
            .passThrough)
    t.equal("Cmd+X still cuts when only cut/paste is enabled",
            CutStateMachine().handle(Input(key: .x, phase: .down, enabledFeatures: [.cutPaste])),
            .swallowAndCopy)

    // The mirror case: Delete wanted, cut/paste not.
    t.equal("Delete still trashes when only trash is enabled",
            CutStateMachine().handle(Input(key: .delete, phase: .down, enabledFeatures: [.trash])),
            .swallowAndTrash)
    t.equal("Cmd+X passes through when only trash is enabled",
            CutStateMachine().handle(Input(key: .x, phase: .down, enabledFeatures: [.trash])),
            .passThrough)
    // Must be armed first: on an idle machine rule 7 returns .passThrough anyway,
    // so the assertion would hold even with per-feature gating reverted.
    let armedButCutPasteOff = CutStateMachine()
    _ = armedButCutPasteOff.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    armedButCutPasteOff.resolveArming(currentChangeCount: 11)
    t.equal("an armed cut cannot paste when only trash is enabled",
            armedButCutPasteOff.handle(
                Input(key: .v, phase: .down, enabledFeatures: [.trash], pasteboardChangeCount: 11)),
            .passThrough)

    // Disabling cut/paste mid-cut must not leave a paste armed.
    let disabledMidCut = CutStateMachine()
    _ = disabledMidCut.handle(Input(key: .x, phase: .down, pasteboardChangeCount: 10))
    disabledMidCut.resolveArming(currentChangeCount: 11)
    t.equal("a pending cut cannot paste once cut/paste is switched off",
            disabledMidCut.handle(Input(key: .v, phase: .down, enabledFeatures: [.trash], pasteboardChangeCount: 11)),
            .passThrough)


    t.section("Modifier gate — what CmdX refuses to touch")

    func gate(_ key: Key, _ m: ModifierGate.Modifiers) -> Bool {
        ModifierGate.shouldConsider(key: key, modifiers: m)
    }

    t.check("bare Delete is ours", gate(.delete, .init()))
    t.check("Cmd+Delete is Finder's own move-to-Trash, not ours",
            !gate(.delete, .init(command: true)))
    t.check("Option+Delete deletes a word in text, not ours",
            !gate(.delete, .init(option: true)))
    t.check("Shift+Delete is not ours", !gate(.delete, .init(shift: true)))
    t.check("Ctrl+Delete is not ours", !gate(.delete, .init(control: true)))
    t.check("fn+Delete forward-deletes, not ours", !gate(.delete, .init(fn: true)))
    // The one that must never regress: this is permanent deletion, no Trash, no undo.
    t.check("Cmd+Option+Delete (PERMANENT delete) is never ours",
            !gate(.delete, .init(command: true, option: true)))

    t.check("Cmd+X is ours", gate(.x, .init(command: true)))
    t.check("Cmd+V is ours", gate(.v, .init(command: true)))
    t.check("bare X is not ours", !gate(.x, .init()))
    t.check("Cmd+Option+V is Finder's native move, not ours",
            !gate(.v, .init(command: true, option: true)))
    t.check("Cmd+Shift+V is paste-and-match-style, not ours",
            !gate(.v, .init(command: true, shift: true)))
    t.check("Cmd+Ctrl+X is not ours", !gate(.x, .init(command: true, control: true)))

    t.finish()
}

run()

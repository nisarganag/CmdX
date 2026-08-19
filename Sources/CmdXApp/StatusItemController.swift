import AppKit

@MainActor
final class StatusItemController {
    private let statusItem: NSStatusItem

    var accessibilityGranted = false {
        didSet {
            rebuildMenu()
            updateIcon()
        }
    }

    /// Whether the event tap is actually installed — distinct from
    /// `accessibilityGranted`, which only means permission was granted. A grant
    /// can be true while the tap itself failed to come up (see AppDelegate's
    /// retry logic), and the menu must not claim things are fine when they are not.
    var tapRunning = false {
        didSet {
            rebuildMenu()
            updateIcon()
        }
    }

    var onToggleEnabled: ((Bool) -> Void)?
    private(set) var isEnabled = true {
        didSet { updateIcon() }
    }

    private var isArmed = false

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setIcon(armed: false)
        rebuildMenu()
    }

    /// Called by the event tap whenever a cut is armed or cleared.
    func setIcon(armed: Bool) {
        isArmed = armed
        updateIcon()
    }

    /// Filled scissors mean a cut is pending; outline means idle; dimmed means
    /// CmdX is switched off or has no Accessibility permission, so Cmd+X and
    /// Cmd+V are currently doing whatever macOS does by default.
    private func updateIcon() {
        let active = isEnabled && accessibilityGranted && tapRunning
        let name = isArmed ? "scissors.circle.fill" : "scissors"
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "CmdX")
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.alphaValue = active ? 1.0 : 0.4
    }

    func rebuildMenu() {
        let menu = NSMenu()

        let toggle = NSMenuItem(
            title: "Cut & Paste Enabled",
            action: #selector(toggleEnabled),
            keyEquivalent: "")
        toggle.target = self
        toggle.state = isEnabled ? .on : .off
        menu.addItem(toggle)

        let login = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLoginItem),
            keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)

        menu.addItem(.separator())

        if accessibilityGranted {
            let title = tapRunning
                ? "Accessibility: Granted"
                : "Accessibility: Granted — tap not running"
            menu.addItem(withTitle: title, action: nil, keyEquivalent: "")
        } else {
            let item = NSMenuItem(
                title: "Accessibility: Not Granted — Open Settings…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: "")
            item.target = self
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(withTitle: "⌘X cuts · ⌘V pastes in Finder", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "CmdX 1.0.0", action: nil, keyEquivalent: "")

        let quit = NSMenuItem(title: "Quit CmdX", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    @objc private func toggleEnabled() {
        isEnabled.toggle()
        onToggleEnabled?(isEnabled)
        rebuildMenu()
    }

    @objc private func toggleLoginItem() {
        let target = !LoginItem.isEnabled
        if let failure = LoginItem.setEnabled(target) {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText =
                failure + "\n\nCmdX usually needs to live in /Applications for this to work."
            alert.runModal()
        }
        rebuildMenu()
    }

    @objc private func openAccessibilitySettings() {
        PermissionMonitor.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

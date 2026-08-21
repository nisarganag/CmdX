import AppKit
import CmdXCore

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

    var onToggleEnabled: ((Set<Feature>) -> Void)?
    private(set) var enabledFeatures: Set<Feature> = Set(Feature.allCases) {
        didSet { updateIcon() }
    }

    /// Applies the persisted choice at launch without echoing it back to disk.
    func setEnabledFeatures(_ features: Set<Feature>) {
        enabledFeatures = features
        rebuildMenu()
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
        let active = !enabledFeatures.isEmpty && accessibilityGranted && tapRunning
        let name = isArmed ? "scissors.circle.fill" : "scissors"
        // Stock SF Symbols render heavy in the menu bar next to Apple's own
        // items. An explicit lighter weight and a slightly smaller size for the
        // filled variant keep both states optically the same size.
        let config = NSImage.SymbolConfiguration(
            pointSize: isArmed ? 14.0 : 15.5,
            weight: .regular,
            scale: .medium)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "CmdX")?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        statusItem.button?.image = image
        statusItem.button?.alphaValue = active ? 1.0 : 0.4
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // View-based rows so the menu stays open across several clicks, and so the
        // labels can share a fixed shortcut column instead of being padded with
        // spaces that only line up in a monospaced font.
        addRow(to: menu,
               shortcut: "⌘X / ⌘V",
               label: "Cut and paste files",
               isOn: enabledFeatures.contains(.cutPaste)) { [weak self] _ in
            self?.toggle(.cutPaste)
        }

        addRow(to: menu,
               shortcut: "⌫",
               label: "Delete to Trash",
               isOn: enabledFeatures.contains(.trash)) { [weak self] _ in
            self?.toggle(.trash)
        }

        addRow(to: menu,
               shortcut: "",
               label: "Launch at login",
               isOn: LoginItem.isEnabled) { [weak self] _ in
            self?.setLoginItem()
        }

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
        menu.addItem(withTitle: "⌘X cut · ⌘V paste · ⌫ trash", action: nil, keyEquivalent: "")
        menu.addItem(withTitle: "CmdX 1.1.0", action: nil, keyEquivalent: "")

        let quit = NSMenuItem(title: "Quit CmdX", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func addRow(
        to menu: NSMenu,
        shortcut: String,
        label: String,
        isOn: Bool,
        onToggle: @escaping (Bool) -> Void
    ) {
        let item = NSMenuItem()
        item.view = ToggleMenuRow(
            shortcut: shortcut, label: label, isOn: isOn, onToggle: onToggle)
        menu.addItem(item)
    }

    private func toggle(_ feature: Feature) {
        if enabledFeatures.contains(feature) {
            enabledFeatures.remove(feature)
        } else {
            enabledFeatures.insert(feature)
        }
        onToggleEnabled?(enabledFeatures)
    }

    private func setLoginItem() {
        let target = !LoginItem.isEnabled
        if let failure = LoginItem.setEnabled(target) {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at Login"
            alert.informativeText =
                failure + "\n\nCmdX usually needs to live in /Applications for this to work."
            alert.runModal()
            rebuildMenu()
        }
    }

    @objc private func openAccessibilitySettings() {
        PermissionMonitor.openSettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

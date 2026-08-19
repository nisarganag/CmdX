import AppKit
@preconcurrency import ApplicationServices
import Foundation

/// Tracks the Accessibility grant. `CGEvent.tapCreate` returns nil without it, so
/// the app polls and starts the tap the moment the user approves — no relaunch.
@MainActor
final class PermissionMonitor {
    private(set) var isTrusted: Bool
    private var timer: Timer?
    private let onChange: (Bool) -> Void

    /// Invoked on every 2-second poll tick with the current trust value, whether
    /// or not it changed — unlike `onChange`. Lets the caller retry starting the
    /// event tap when trust was already granted but `tapCreate` failed the first
    /// time (e.g. at login, before WindowServer is fully up).
    var onPoll: ((Bool) -> Void)?

    init(onChange: @escaping (Bool) -> Void) {
        self.isTrusted = AXIsProcessTrusted()
        self.onChange = onChange
    }

    func start(promptIfNeeded: Bool) {
        if promptIfNeeded, !isTrusted {
            let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
        }
        onChange(isTrusted)

        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = AXIsProcessTrusted()
                self.onPoll?(now)
                guard now != self.isTrusted else { return }
                self.isTrusted = now
                self.onChange(now)
            }
        }
    }

    static func openSettings() {
        guard let url = URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }
}

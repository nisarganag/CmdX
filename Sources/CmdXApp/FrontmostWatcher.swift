import AppKit

/// Caches whether Finder is frontmost, updated from workspace notifications, so
/// the event tap callback never performs an app lookup inline.
@MainActor
final class FrontmostWatcher {
    static let finderBundleID = "com.apple.finder"

    private(set) var isFinderFrontmost = false
    private(set) var finderPID: pid_t = 0

    init() {
        let current = NSWorkspace.shared.frontmostApplication
        refresh(bundleID: current?.bundleIdentifier, pid: current?.processIdentifier)

        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            // Reduce to Sendable value types before crossing into the isolated
            // closure: NSRunningApplication and Notification are not Sendable, and
            // Swift 6 rejects capturing them here.
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
            let bundleID = app?.bundleIdentifier
            let pid = app?.processIdentifier
            MainActor.assumeIsolated {
                self?.refresh(bundleID: bundleID, pid: pid)
            }
        }
    }

    private func refresh(bundleID: String?, pid: pid_t?) {
        isFinderFrontmost = bundleID == Self.finderBundleID
        // Keep the last known Finder pid even after it deactivates: the AX query
        // needs it, and re-resolving it on every keystroke would be wasteful.
        if isFinderFrontmost, let pid {
            finderPID = pid
        }
    }
}

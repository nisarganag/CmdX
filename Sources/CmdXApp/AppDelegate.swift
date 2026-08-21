import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?
    private var frontmost: FrontmostWatcher?
    private var focus: FocusInspector?
    private var permissions: PermissionMonitor?
    private var tap: EventTapService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let status = StatusItemController()
        statusItem = status

        let watcher = FrontmostWatcher()
        let inspector = FocusInspector()
        frontmost = watcher
        focus = inspector

        let service = EventTapService(frontmost: watcher, focus: inspector)
        service.onArmedChange = { armed in
            status.setIcon(armed: armed)
        }
        tap = service

        let saved = Preferences.loadEnabledFeatures()
        status.setEnabledFeatures(saved)
        service.enabledFeatures = saved

        status.onToggleEnabled = { features in
            service.enabledFeatures = features
            Preferences.save(features)
        }

        let monitor = PermissionMonitor { granted in
            status.accessibilityGranted = granted
            if granted {
                service.start()
            } else {
                service.stop()
            }
            status.tapRunning = service.isRunning
        }
        // Trust can already be true at login while tapCreate still fails (e.g.
        // WindowServer not fully up yet, or a stale ad-hoc TCC record). onChange
        // alone would never retry, since it only fires on a value change — every
        // poll tick gets a chance to bring the tap up if it isn't already.
        monitor.onPoll = { granted in
            guard granted, !service.isRunning else { return }
            service.start()
            status.tapRunning = service.isRunning
        }
        permissions = monitor
        monitor.start(promptIfNeeded: true)
    }
}

import ServiceManagement

/// Wraps SMAppService so the menu can show and toggle "Launch at Login".
@MainActor
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// Returns nil on success, or a message describing why it failed. Registration
    /// is rejected for apps in some locations, so failure must be surfaced rather
    /// than silently leaving the checkbox unchanged.
    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}

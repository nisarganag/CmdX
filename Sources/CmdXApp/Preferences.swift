import CmdXCore
import Foundation

/// Persists which features are switched on. Without this the toggles would
/// silently reset on every launch — and since CmdX starts at login, a user who
/// deliberately turned Delete off would find it back on the next morning.
enum Preferences {
    private static let key = "enabledFeatures"

    private static let names: [Feature: String] = [
        .cutPaste: "cutPaste",
        .trash: "trash",
    ]

    /// Defaults to everything on for a first run. An empty stored array is a
    /// deliberate "both off" and is preserved, which is why absence of the key —
    /// not emptiness — is what triggers the default.
    static func loadEnabledFeatures() -> Set<Feature> {
        guard let stored = UserDefaults.standard.array(forKey: key) as? [String] else {
            return Set(Feature.allCases)
        }
        return Set(Feature.allCases.filter { stored.contains(names[$0] ?? "") })
    }

    static func save(_ features: Set<Feature>) {
        UserDefaults.standard.set(
            Feature.allCases.filter(features.contains).compactMap { names[$0] },
            forKey: key)
    }
}

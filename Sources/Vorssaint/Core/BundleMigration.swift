import AppKit

/// Cleans up after the app was renamed on disk: the bundle filename went from
/// "Vorssaint Utils.app" to "Vorssaint.app". The self-updater already replaces
/// the old bundle, but a manual drag-install of the new DMG, or an interrupted
/// update, can leave the previous "Vorssaint Utils.app" next to the new one.
/// Both carry the same bundle id, so the system would otherwise list two
/// identical apps and keep stale "Vorssaint Utils" entries in Spotlight, Login
/// Items and the permission panes.
///
/// This is intentionally conservative: it moves a bundle to the Trash (so the
/// action is reversible) only when that bundle is not the running app and
/// carries our own bundle id, i.e. it is provably an older copy of us. Granted
/// permissions are keyed to the bundle id, which never changed, so they stay
/// with the surviving bundle. Runs on every launch; it is a no-op once clean.
enum BundleMigration {
    private static let legacyBundleNames = ["Vorssaint Utils.app"]

    static func cleanUpLegacyBundles() {
        guard let myID = Bundle.main.bundleIdentifier else { return }
        let running = Bundle.main.bundleURL.resolvingSymlinksInPath()

        // Look next to the running bundle and in /Applications.
        var searchDirs = [running.deletingLastPathComponent().path]
        let applications = "/Applications"
        if !searchDirs.contains(applications) { searchDirs.append(applications) }

        for dir in searchDirs {
            for name in legacyBundleNames {
                let candidate = URL(fileURLWithPath: dir).appendingPathComponent(name)
                guard candidate.resolvingSymlinksInPath() != running,
                      FileManager.default.fileExists(atPath: candidate.path),
                      Bundle(url: candidate)?.bundleIdentifier == myID else { continue }
                try? FileManager.default.trashItem(at: candidate, resultingItemURL: nil)
            }
        }
    }
}

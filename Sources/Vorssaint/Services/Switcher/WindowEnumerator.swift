import AppKit
import CoreGraphics

/// Builds the list of switchable windows from the window server.
///
/// `CGWindowListCopyWindowInfo` is queried with `.optionAll` so windows that
/// are minimized or parked on other Spaces are included. The result is then
/// ordered by the app activation MRU (see `AppActivationTracker`), so the
/// switcher matches the system ⌘Tab toggle. Window titles require Screen
/// Recording on modern macOS — without it entries fall back to app names.
enum WindowEnumerator {
    /// Windows larger than this are considered real, switchable windows.
    private static let minimumSize = CGSize(width: 80, height: 60)
    /// Hard cap to keep the switcher readable and captures cheap.
    private static let maximumCount = 24

    static func listWindows() -> [SwitcherItem] {
        guard let raw = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else {
            return []
        }

        let ownPid = ProcessInfo.processInfo.processIdentifier
        var regularApps: [pid_t: String] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            regularApps[app.processIdentifier] = app.localizedName ?? ""
        }

        var seen = Set<CGWindowID>()
        var windows: [SwitcherItem] = []

        for info in raw {
            guard windows.count < maximumCount else { break }
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
                  let windowID = info[kCGWindowNumber as String] as? CGWindowID,
                  !seen.contains(windowID),
                  let pid = info[kCGWindowOwnerPID as String] as? pid_t,
                  pid != ownPid,
                  let appName = regularApps[pid],
                  let boundsDict = info[kCGWindowBounds as String] as? [String: CGFloat]
            else { continue }

            let frame = CGRect(x: boundsDict["X"] ?? 0,
                               y: boundsDict["Y"] ?? 0,
                               width: boundsDict["Width"] ?? 0,
                               height: boundsDict["Height"] ?? 0)
            guard frame.width >= minimumSize.width, frame.height >= minimumSize.height else { continue }

            if let alpha = info[kCGWindowAlpha as String] as? Double, alpha == 0 { continue }

            let title = info[kCGWindowName as String] as? String ?? ""
            let isOnScreen = info[kCGWindowIsOnscreen as String] as? Bool ?? false

            // Off-screen *and* untitled windows are usually invisible helpers
            // (web pickers, Electron shells), not something to switch to.
            if !isOnScreen && title.isEmpty { continue }

            seen.insert(windowID)
            windows.append(.window(id: windowID,
                                   title: title,
                                   appName: appName,
                                   pid: pid,
                                   isOnScreen: isOnScreen,
                                   frame: frame))
        }
        if UserDefaults.standard.bool(forKey: DefaultsKey.switcherMergeTabs) {
            windows = groupWindowsByApp(windows)
        }
        return orderByActivation(windows)
    }

    /// Groups windows by app in most-recently-used order while preserving the
    /// window server's front-to-back order within each app. A stable sort is
    /// required so the within-app order survives the regrouping. This is what
    /// puts the window you were just in (including another window of the same
    /// app) right next to the current one.
    private static func orderByActivation(_ windows: [SwitcherItem]) -> [SwitcherItem] {
        let tracker = AppActivationTracker.shared
        return windows.enumerated().sorted { lhs, rhs in
            let rankL = tracker.rank(of: lhs.element.pid)
            let rankR = tracker.rank(of: rhs.element.pid)
            return rankL != rankR ? rankL < rankR : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Collapses every window of an app into a single entry, so an app shows once
    /// in the switcher instead of once per window (or tab). Keeps one
    /// representative per app, preferring the on-screen, front window so its title
    /// and thumbnail are the one you would expect when switching to that app.
    private static func groupWindowsByApp(_ windows: [SwitcherItem]) -> [SwitcherItem] {
        var indexByPid: [pid_t: Int] = [:]
        var grouped: [SwitcherItem] = []
        for window in windows {
            if let index = indexByPid[window.pid] {
                // Another window of the same app: prefer an on-screen window as
                // the representative when the one we kept is off-screen.
                if window.isOnScreen && !grouped[index].isOnScreen {
                    grouped[index] = window
                }
            } else {
                indexByPid[window.pid] = grouped.count
                grouped.append(window)
            }
        }
        return grouped
    }
}

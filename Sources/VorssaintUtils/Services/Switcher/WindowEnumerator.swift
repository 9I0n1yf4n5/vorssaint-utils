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
        return orderByActivation(windows)
    }

    /// Groups windows by app in most-recently-used order while preserving the
    /// window server's front-to-back order within each app. A stable sort is
    /// required so the within-app order survives the regrouping.
    private static func orderByActivation(_ windows: [SwitcherItem]) -> [SwitcherItem] {
        let tracker = AppActivationTracker.shared
        return windows.enumerated().sorted { lhs, rhs in
            let rankL = tracker.rank(of: lhs.element.pid)
            let rankR = tracker.rank(of: rhs.element.pid)
            return rankL != rankR ? rankL < rankR : lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Splices browser tabs into the window list: each browser window that has
    /// scripting data is replaced, in place, by one entry per tab (the active
    /// tab keeps the window's thumbnail). Windows without tab data — other
    /// apps, denied automation, mismatched titles — stay as plain entries.
    static func mergingTabs(_ windows: [SwitcherItem], tabs: [BrowserTab]) -> [SwitcherItem] {
        guard !tabs.isEmpty else { return windows }

        var byWindow: [pid_t: [String: [BrowserTab]]] = [:]
        for tab in tabs {
            byWindow[tab.pid, default: [:]][tab.windowName, default: []].append(tab)
        }

        var result: [SwitcherItem] = []
        for window in windows {
            guard case .window = window.kind,
                  let group = byWindow[window.pid]?[window.title],
                  !group.isEmpty
            else {
                result.append(window)
                continue
            }
            for tab in group.sorted(by: { $0.tabIndex < $1.tabIndex }) {
                result.append(.tab(tab, of: window))
            }
        }
        return result
    }
}

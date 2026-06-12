import AppKit
import CoreGraphics

/// One selectable entry in the switcher: a real window of a regular app, or a
/// single browser tab. Multiple windows of the same app — and multiple tabs of
/// the same browser window — appear as independent entries.
struct SwitcherItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case window
        case browserTab(BrowserTab)
    }

    let id: String
    let kind: Kind
    let title: String
    let appName: String
    let pid: pid_t
    /// The backing CGWindow: thumbnails and AX raising go through it. For a
    /// tab it is the window that hosts the tab (when matched).
    let windowID: CGWindowID?
    let isOnScreen: Bool
    let frame: CGRect

    /// Thumbnails are only honest for entries whose backing window currently
    /// renders their content: plain windows and each window's *active* tab.
    /// Background tabs fall back to the app icon.
    var previewWindowID: CGWindowID? {
        switch kind {
        case .window:
            return windowID
        case let .browserTab(tab):
            return tab.isActive ? windowID : nil
        }
    }

    /// Label shown under the thumbnail; untitled windows fall back to the app name.
    var displayTitle: String {
        title.isEmpty ? appName : title
    }

    var appIcon: NSImage? {
        NSRunningApplication(processIdentifier: pid)?.icon
    }

    static func window(id: CGWindowID, title: String, appName: String, pid: pid_t,
                       isOnScreen: Bool, frame: CGRect) -> SwitcherItem {
        SwitcherItem(id: "w:\(id)", kind: .window, title: title, appName: appName,
                     pid: pid, windowID: id, isOnScreen: isOnScreen, frame: frame)
    }

    static func tab(_ tab: BrowserTab, of window: SwitcherItem) -> SwitcherItem {
        SwitcherItem(id: "t:\(tab.bundleId):\(tab.windowIndex):\(tab.tabIndex)",
                     kind: .browserTab(tab),
                     title: tab.title,
                     appName: window.appName,
                     pid: window.pid,
                     windowID: window.windowID,
                     isOnScreen: window.isOnScreen,
                     frame: window.frame)
    }
}

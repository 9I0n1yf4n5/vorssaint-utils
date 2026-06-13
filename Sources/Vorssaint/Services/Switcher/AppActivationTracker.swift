import AppKit

/// Keeps a most-recently-used order of applications by watching activation
/// notifications. The switcher orders its windows by this, so a quick
/// ⌘Tab→release always lands on the previous app, and tapping again returns —
/// the deterministic toggle the live window-server z-order can't guarantee
/// (its order lags a freshly activated window by a frame or two).
final class AppActivationTracker {
    static let shared = AppActivationTracker()

    private(set) var mru: [pid_t] = []
    private let ownPid = ProcessInfo.processInfo.processIdentifier

    private init() {}

    func start() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(appActivated(_:)),
                           name: NSWorkspace.didActivateApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(appTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        if let front = NSWorkspace.shared.frontmostApplication {
            record(front.processIdentifier)
        }
    }

    /// MRU rank of an app; unseen apps sort after every known one.
    func rank(of pid: pid_t) -> Int {
        mru.firstIndex(of: pid) ?? Int.max
    }

    /// The app the user is currently in (front of the MRU).
    var frontmostPid: pid_t? { mru.first }

    @objc private func appActivated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        record(app.processIdentifier)
    }

    @objc private func appTerminated(_ note: Notification) {
        guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        mru.removeAll { $0 == app.processIdentifier }
    }

    private func record(_ pid: pid_t) {
        // The non-activating switcher panel never steals focus, but guard our
        // own pid anyway so it can't pollute the order.
        guard pid != ownPid else { return }
        mru.removeAll { $0 == pid }
        mru.insert(pid, at: 0)
    }
}

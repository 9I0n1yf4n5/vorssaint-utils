import AppKit
import Foundation

/// One browser tab, as discovered through the browser's scripting interface.
struct BrowserTab: Equatable {
    let bundleId: String
    let pid: pid_t
    /// AppleScript window index (1-based) and the window's title, used to match
    /// the tab to its CGWindow.
    let windowIndex: Int
    let windowName: String
    let tabIndex: Int
    let isActive: Bool
    let title: String
}

/// Enumerates open tabs of running browsers via Apple Events, so the switcher
/// can offer every tab — not just the window's visible one. Safari and the
/// Chromium family share almost the same scripting dialect.
///
/// macOS shows an Automation consent prompt per browser on first use; denied
/// or unscriptable browsers are silently skipped and keep their plain window
/// entry in the switcher. Results are cached so a session can render
/// instantly with slightly stale data while a fresh sweep runs.
final class BrowserTabService {
    static let shared = BrowserTabService()

    private(set) var cached: [BrowserTab] = []
    private let queue = DispatchQueue(label: "com.vorssaint.utils.browser-tabs", qos: .userInitiated)

    private enum Dialect {
        case safari, chromium
    }

    /// Browsers we know how to talk to.
    private static let supported: [String: Dialect] = [
        "com.apple.Safari": .safari,
        "com.google.Chrome": .chromium,
        "com.microsoft.edgemac": .chromium,
        "com.brave.Browser": .chromium,
        "com.vivaldi.Vivaldi": .chromium,
    ]

    private init() {}

    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: DefaultsKey.switcherShowBrowserTabs)
    }

    /// Tabs usable for an instant render: the last sweep's result, unless the
    /// feature was switched off since.
    var cachedIfEnabled: [BrowserTab] {
        isEnabled ? cached : []
    }

    /// Sweeps every running supported browser off the main thread and delivers
    /// the merged result (also updating the cache) on the main thread.
    func refresh(completion: @escaping ([BrowserTab]) -> Void) {
        guard isEnabled else {
            cached = []
            completion([])
            return
        }
        let browsers = NSWorkspace.shared.runningApplications.compactMap { app -> (String, pid_t, Dialect)? in
            guard let bundleId = app.bundleIdentifier,
                  let dialect = Self.supported[bundleId] else { return nil }
            return (bundleId, app.processIdentifier, dialect)
        }
        guard !browsers.isEmpty else {
            DispatchQueue.main.async {
                self.cached = []
                completion([])
            }
            return
        }

        queue.async {
            var tabs: [BrowserTab] = []
            for (bundleId, pid, dialect) in browsers {
                tabs.append(contentsOf: Self.listTabs(bundleId: bundleId, pid: pid, dialect: dialect))
            }
            DispatchQueue.main.async {
                self.cached = tabs
                completion(tabs)
            }
        }
    }

    /// Makes `tab` the current tab of its window. Runs the script off-main;
    /// the caller raises the window/app afterwards on its own.
    func activate(_ tab: BrowserTab, completion: @escaping () -> Void) {
        let source: String
        switch Self.supported[tab.bundleId] {
        case .safari:
            source = """
            with timeout of 2 seconds
                tell application id "\(tab.bundleId)"
                    tell window \(tab.windowIndex)
                        set current tab to tab \(tab.tabIndex)
                        set index to 1
                    end tell
                end tell
            end timeout
            """
        case .chromium:
            source = """
            with timeout of 2 seconds
                tell application id "\(tab.bundleId)"
                    set active tab index of window \(tab.windowIndex) to \(tab.tabIndex)
                    set index of window \(tab.windowIndex) to 1
                end tell
            end timeout
            """
        case nil:
            completion()
            return
        }
        queue.async {
            _ = Self.runAppleScript(source)
            DispatchQueue.main.async(execute: completion)
        }
    }

    // MARK: - Enumeration scripts

    private static func listTabs(bundleId: String, pid: pid_t, dialect: Dialect) -> [BrowserTab] {
        // Output: one tab per line, fields separated by an ASCII unit
        // separator so titles with tabs/commas can't break parsing.
        let script: String
        switch dialect {
        case .safari:
            script = """
            set u to character id 31
            set out to ""
            with timeout of 2 seconds
                tell application id "\(bundleId)"
                    set wi to 0
                    repeat with w in windows
                        set wi to wi + 1
                        try
                            set cur to index of current tab of w
                            set wn to name of w
                            set ti to 0
                            repeat with t in tabs of w
                                set ti to ti + 1
                                set out to out & wi & u & ti & u & cur & u & wn & u & (name of t) & linefeed
                            end repeat
                        end try
                    end repeat
                end tell
            end timeout
            return out
            """
        case .chromium:
            script = """
            set u to character id 31
            set out to ""
            with timeout of 2 seconds
                tell application id "\(bundleId)"
                    set wi to 0
                    repeat with w in windows
                        set wi to wi + 1
                        try
                            set cur to active tab index of w
                            set wn to title of w
                            set ti to 0
                            repeat with t in tabs of w
                                set ti to ti + 1
                                set out to out & wi & u & ti & u & cur & u & wn & u & (title of t) & linefeed
                            end repeat
                        end try
                    end repeat
                end tell
            end timeout
            return out
            """
        }

        guard let output = runAppleScript(script) else { return [] }

        let separator = Character(UnicodeScalar(31))
        var tabs: [BrowserTab] = []
        for line in output.split(separator: "\n") {
            let fields = line.split(separator: separator, omittingEmptySubsequences: false)
            guard fields.count == 5,
                  let windowIndex = Int(fields[0]),
                  let tabIndex = Int(fields[1]),
                  let activeIndex = Int(fields[2])
            else { continue }
            tabs.append(BrowserTab(bundleId: bundleId,
                                   pid: pid,
                                   windowIndex: windowIndex,
                                   windowName: String(fields[3]),
                                   tabIndex: tabIndex,
                                   isActive: tabIndex == activeIndex,
                                   title: String(fields[4])))
        }
        return tabs
    }

    /// `osascript` in a child process: thread-safe, and a hung browser can be
    /// killed instead of stalling the app.
    private static func runAppleScript(_ source: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", source]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }

        let killer = DispatchWorkItem { process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 3, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()

        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

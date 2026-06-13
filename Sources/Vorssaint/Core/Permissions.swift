import AppKit
import ApplicationServices
import Combine
import CoreGraphics

/// Central place to check, request and watch the TCC permissions the app uses.
/// Accessibility powers the scroll inverter and the switcher's event tap;
/// Screen Recording powers window titles and thumbnails in the switcher.
final class Permissions: ObservableObject {
    static let shared = Permissions()

    @Published private(set) var accessibility = false
    @Published private(set) var screenRecording = false
    /// Optional — only used to make the uninstaller's scan more thorough by
    /// reaching protected locations. There is no API prompt for it; the user
    /// grants it in System Settings.
    @Published private(set) var fullDiskAccess = false

    private init() {
        refresh()
        // Cheap always-on watch: features come alive the moment a permission
        // is granted in System Settings, no relaunch or open window required.
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        // Re-check the instant the user returns from System Settings, so a
        // freshly granted permission reflects immediately instead of up to a
        // tick later.
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()
        let fda = Self.probeFullDiskAccess()
        DispatchQueue.main.async {
            if self.accessibility != ax { self.accessibility = ax }
            if self.screenRecording != sr { self.screenRecording = sr }
            if self.fullDiskAccess != fda { self.fullDiskAccess = fda }
        }
    }

    /// Reading the TCC database succeeds only with Full Disk Access — the
    /// standard, prompt-free way to detect it.
    private static func probeFullDiskAccess() -> Bool {
        let path = (NSHomeDirectory() as NSString)
            .appendingPathComponent("Library/Application Support/com.apple.TCC/TCC.db")
        guard let handle = FileHandle(forReadingAtPath: path) else { return false }
        handle.closeFile()
        return true
    }

    /// Shows the system Accessibility prompt (once per TCC reset).
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    /// Shows the system Screen Recording prompt (once per TCC reset).
    func requestScreenRecording() {
        CGRequestScreenCaptureAccess()
    }

    func openAccessibilitySettings() {
        open(pane: "Privacy_Accessibility")
    }

    func openScreenRecordingSettings() {
        open(pane: "Privacy_ScreenCapture")
    }

    func openFullDiskAccessSettings() {
        open(pane: "Privacy_AllFiles")
    }

    /// Full Disk Access has no prompt API, and an app only shows up (toggled
    /// off) in its System Settings list once it has *attempted* to read a
    /// protected location. So touch a few data-vault paths to register the app,
    /// then open the pane — now the toggle is there to flip on.
    func requestFullDiskAccess() {
        DispatchQueue.global(qos: .userInitiated).async {
            let home = NSHomeDirectory()
            let fm = FileManager.default
            let probes = [
                "Library/Application Support/com.apple.TCC/TCC.db",
                "Library/Safari",
                "Library/Cookies",
                "Library/Application Support/MobileSync",
            ].map { (home as NSString).appendingPathComponent($0) }
            // The denied attempt itself is what registers the app with TCC.
            for path in probes {
                _ = try? fm.contentsOfDirectory(atPath: path)
                if let handle = FileHandle(forReadingAtPath: path) { try? handle.close() }
            }
            DispatchQueue.main.async { self.openFullDiskAccessSettings() }
        }
    }

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }
}

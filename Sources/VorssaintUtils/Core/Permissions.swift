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

    private init() {
        refresh()
        // Cheap always-on watch: features come alive the moment a permission
        // is granted in System Settings, no relaunch or open window required.
        let timer = Timer(timeInterval: 2.5, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        RunLoop.main.add(timer, forMode: .common)
    }

    func refresh() {
        let ax = AXIsProcessTrusted()
        let sr = CGPreflightScreenCaptureAccess()
        DispatchQueue.main.async {
            if self.accessibility != ax { self.accessibility = ax }
            if self.screenRecording != sr { self.screenRecording = sr }
        }
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

    private func open(pane: String) {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!
        NSWorkspace.shared.open(url)
    }
}

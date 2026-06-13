import AppKit
import ApplicationServices

/// Resolves a CGWindowID to its Accessibility element. Exported by
/// ApplicationServices and used by every macOS window switcher; there is no
/// public alternative for this mapping.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement,
                                   _ windowID: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Brings a switcher selection to the front: unminimizes if needed, raises the
/// exact window through Accessibility and activates the owning app. When the
/// window lives on another Space, activating the app lets Mission Control carry
/// the user there.
enum WindowActivator {
    static func activate(_ item: SwitcherItem) {
        raiseWindow(of: item)
    }

    private static func raiseWindow(of item: SwitcherItem) {
        guard let app = NSRunningApplication(processIdentifier: item.pid) else { return }

        if Permissions.shared.accessibility, let axWindow = axElement(for: item) {
            var minimized: CFTypeRef?
            if AXUIElementCopyAttributeValue(axWindow, kAXMinimizedAttribute as CFString, &minimized) == .success,
               (minimized as? Bool) == true {
                AXUIElementSetAttributeValue(axWindow, kAXMinimizedAttribute as CFString, kCFBooleanFalse)
            }
            AXUIElementPerformAction(axWindow, kAXRaiseAction as CFString)
            AXUIElementSetAttributeValue(axWindow, kAXMainAttribute as CFString, kCFBooleanTrue)
        }

        app.activate(options: [])
    }

    private static func axElement(for item: SwitcherItem) -> AXUIElement? {
        let windowID = item.windowID
        let axApp = AXUIElementCreateApplication(item.pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(axApp, kAXWindowsAttribute as CFString, &value) == .success,
              let axWindows = value as? [AXUIElement]
        else { return nil }

        for axWindow in axWindows {
            var id: CGWindowID = 0
            if _AXUIElementGetWindow(axWindow, &id) == .success, id == windowID {
                return axWindow
            }
        }
        return nil
    }
}

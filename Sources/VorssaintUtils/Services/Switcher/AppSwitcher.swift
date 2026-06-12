import AppKit
import Combine
import CoreGraphics
import SwiftUI

/// The window switcher: a global event tap takes over ⌘Tab, and while ⌘ is held
/// a non-activating panel cycles through real windows — release commits, Q quits
/// the highlighted app, Esc cancels. The panel joins every Space and fullscreen
/// app, so the switcher is available wherever the user is.
final class AppSwitcher: ObservableObject {
    static let shared = AppSwitcher()

    @Published private(set) var windows: [SwitcherItem] = []
    @Published private(set) var previews: [CGWindowID: CGImage] = [:]
    @Published private(set) var selectedIndex = 0
    @Published private(set) var grid = SwitcherGrid.empty

    private var sessionActive = false
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var panel: NSPanel?

    // The switcher always takes over ⌘Tab to replace the system switcher.
    private let modifierFlag = CGEventFlags.maskCommand
    private let conflictingFlag = CGEventFlags.maskAlternate

    // Virtual key codes handled during a session.
    private enum KeyCode {
        static let tab: Int64 = 48
        static let escape: Int64 = 53
        static let enter: Int64 = 36
        static let q: Int64 = 12
        static let leftArrow: Int64 = 123
        static let rightArrow: Int64 = 124
        static let downArrow: Int64 = 125
        static let upArrow: Int64 = 126
    }

    private init() {}

    /// True while the event tap is installed.
    var isRunning: Bool { tap != nil }

    /// Applies the persisted preference; safe to call repeatedly.
    func syncWithPreferences() {
        let enabled = UserDefaults.standard.bool(forKey: DefaultsKey.switcherEnabled)
        if enabled, Permissions.shared.accessibility {
            installTap()
        } else {
            removeTap()
        }
    }

    // MARK: - Event tap

    private func installTap() {
        guard tap == nil else { return }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue) | CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let switcher = Unmanaged<AppSwitcher>.fromOpaque(userInfo).takeUnretainedValue()
                return switcher.handle(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else { return }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    private func removeTap() {
        if sessionActive { cancelSession() }
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        tap = nil
        runLoopSource = nil
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        switch type {
        case .keyDown:
            return handleKeyDown(event)
        case .flagsChanged:
            if sessionActive, !event.flags.contains(modifierFlag) {
                commitSession()
            }
            return Unmanaged.passUnretained(event)
        default:
            return Unmanaged.passUnretained(event)
        }
    }

    private func handleKeyDown(_ event: CGEvent) -> Unmanaged<CGEvent>? {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        guard sessionActive else {
            // A session starts with ⌘Tab, as long as the combo is not claimed
            // by something else (⌘⌥Tab, ⌃⌘Tab…).
            guard keyCode == KeyCode.tab,
                  flags.contains(modifierFlag),
                  !flags.contains(conflictingFlag),
                  !flags.contains(.maskControl)
            else { return Unmanaged.passUnretained(event) }

            beginSession(reversed: flags.contains(.maskShift))
            return nil
        }

        switch keyCode {
        case KeyCode.tab:
            advanceSelection(by: flags.contains(.maskShift) ? -1 : 1)
        case KeyCode.rightArrow:
            advanceSelection(by: 1)
        case KeyCode.leftArrow:
            advanceSelection(by: -1)
        case KeyCode.downArrow:
            moveSelection(by: grid.columns)
        case KeyCode.upArrow:
            moveSelection(by: -grid.columns)
        case KeyCode.q:
            quitSelectedApp()
        case KeyCode.escape:
            cancelSession()
        case KeyCode.enter:
            commitSession()
        default:
            break // Swallow stray keys so they never leak into the focused app.
        }
        return nil
    }

    // MARK: - Session lifecycle

    private func beginSession(reversed: Bool) {
        let baseWindows = WindowEnumerator.listWindows()
        guard !baseWindows.isEmpty else { return }

        // Render immediately with cached tab data (possibly a few seconds
        // stale); a fresh scripting sweep lands shortly after and re-merges.
        let list = WindowEnumerator.mergingTabs(baseWindows, tabs: BrowserTabService.shared.cachedIfEnabled)

        windows = list
        grid = SwitcherGrid.compute(count: list.count, on: screenWithMouse())
        previews = Dictionary(uniqueKeysWithValues: list.compactMap { item in
            item.previewWindowID.flatMap { id in
                WindowPreviewProvider.shared.cachedPreview(for: id).map { (id, $0) }
            }
        })
        if reversed {
            selectedIndex = list.count - 1
        } else if let frontPid = AppActivationTracker.shared.frontmostPid,
                  let firstOther = list.firstIndex(where: { $0.pid != frontPid }) {
            // Default to the previous app (first window not belonging to the
            // app the user is in) — so ⌘Tab→release toggles between two apps.
            selectedIndex = firstOther
        } else {
            selectedIndex = list.count >= 2 ? 1 : 0
        }
        sessionActive = true

        WindowPreviewProvider.shared.refreshPreviews(for: list) { [weak self] windowID, image in
            self?.previews[windowID] = image
        }
        BrowserTabService.shared.refresh { [weak self] tabs in
            self?.applyFreshTabs(tabs, baseWindows: baseWindows)
        }
        showPanel()
    }

    /// Re-merges the item list when the live tab sweep finishes, keeping the
    /// current selection anchored to the same entry.
    private func applyFreshTabs(_ tabs: [BrowserTab], baseWindows: [SwitcherItem]) {
        guard sessionActive else { return }
        let merged = WindowEnumerator.mergingTabs(baseWindows, tabs: tabs)
        guard merged != windows else { return }

        let selectedID = windows.indices.contains(selectedIndex) ? windows[selectedIndex].id : nil
        windows = merged
        if let selectedID, let index = merged.firstIndex(where: { $0.id == selectedID }) {
            selectedIndex = index
        } else {
            selectedIndex = min(selectedIndex, merged.count - 1)
        }
        grid = SwitcherGrid.compute(count: merged.count, on: screenWithMouse())
        resizePanel()
        WindowPreviewProvider.shared.refreshPreviews(for: merged) { [weak self] windowID, image in
            self?.previews[windowID] = image
        }
    }

    func select(index: Int) {
        guard sessionActive, windows.indices.contains(index) else { return }
        selectedIndex = index
    }

    private func advanceSelection(by delta: Int) {
        guard !windows.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + windows.count) % windows.count
    }

    /// Quits the app owning the selected window (⌘Tab → Q), removes its windows
    /// from the grid and keeps the session open — mirroring the system switcher.
    private func quitSelectedApp() {
        guard windows.indices.contains(selectedIndex) else { return }
        let pid = windows[selectedIndex].pid
        NSRunningApplication(processIdentifier: pid)?.terminate()

        let removedBeforeSelection = windows[..<selectedIndex].filter { $0.pid == pid }.count
        windows.removeAll { $0.pid == pid }
        let remaining = Set(windows.compactMap(\.previewWindowID))
        previews = previews.filter { remaining.contains($0.key) }

        guard !windows.isEmpty else {
            endSession()
            return
        }
        selectedIndex = min(max(0, selectedIndex - removedBeforeSelection), windows.count - 1)
        grid = SwitcherGrid.compute(count: windows.count, on: screenWithMouse())
        resizePanel()
    }

    /// Row jump (↑/↓): moves without wrapping so the selection stays put at
    /// the grid edges.
    private func moveSelection(by delta: Int) {
        let target = selectedIndex + delta
        guard windows.indices.contains(target) else { return }
        selectedIndex = target
    }

    /// Activates the current selection. Also used by the panel on click.
    func commitSession() {
        guard sessionActive else { return }
        let selection = windows.indices.contains(selectedIndex) ? windows[selectedIndex] : nil
        endSession()
        if let selection {
            DispatchQueue.main.async {
                WindowActivator.activate(selection)
            }
        }
    }

    private func cancelSession() {
        guard sessionActive else { return }
        endSession()
    }

    private func endSession() {
        sessionActive = false
        WindowPreviewProvider.shared.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - Panel

    private func showPanel() {
        let panel = ensurePanel()
        panel.setContentSize(grid.panelSize)
        centerPanel(panel)
        panel.orderFrontRegardless()
    }

    /// Re-centers the panel after the grid is resized mid-session (e.g. an app
    /// was quit with Q).
    private func resizePanel() {
        guard let panel else { return }
        panel.setContentSize(grid.panelSize)
        centerPanel(panel)
    }

    private func centerPanel(_ panel: NSPanel) {
        let frame = screenWithMouse().visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: frame.midX - size.width / 2,
                                     y: frame.midY - size.height / 2))
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }

        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient, .ignoresCycle]
        panel.contentViewController = NSHostingController(rootView: SwitcherView().environmentObject(self))
        self.panel = panel
        return panel
    }

    private func screenWithMouse() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

/// Grid metrics for one switcher session: large cards laid out in as many
/// rows as needed, sized to the screen under the cursor — no sideways
/// scrolling, no squinting.
struct SwitcherGrid: Equatable {
    let columns: Int
    let rows: Int
    let visibleRows: Int
    let panelSize: CGSize

    static let cardWidth: CGFloat = 288
    static let cardHeight: CGFloat = 214
    static let spacing: CGFloat = 12
    static let padding: CGFloat = 20

    static let empty = SwitcherGrid(columns: 1, rows: 1, visibleRows: 1, panelSize: .zero)

    static func compute(count: Int, on screen: NSScreen) -> SwitcherGrid {
        let usableWidth = screen.visibleFrame.width * 0.92
        let usableHeight = screen.visibleFrame.height * 0.85

        let maxColumns = max(1, Int((usableWidth - padding * 2 + spacing) / (cardWidth + spacing)))
        let columns = min(count, maxColumns)
        let rows = Int(ceil(Double(count) / Double(columns)))

        let maxRows = max(1, Int((usableHeight - padding * 2 + spacing) / (cardHeight + spacing)))
        let visibleRows = min(rows, maxRows)

        let width = CGFloat(columns) * cardWidth + CGFloat(columns - 1) * spacing + padding * 2
        let height = CGFloat(visibleRows) * cardHeight + CGFloat(visibleRows - 1) * spacing + padding * 2
        return SwitcherGrid(columns: columns, rows: rows, visibleRows: visibleRows,
                            panelSize: CGSize(width: width, height: height))
    }
}

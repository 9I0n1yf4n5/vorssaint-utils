// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Vorssaint

import AppKit
import Metal
import QuartzCore

/// Pushes the built-in XDR display past its regular maximum brightness by
/// using the panel's HDR headroom for everything on screen.
///
/// Mechanism: a fullscreen, click-through overlay window holds a Metal layer
/// whose compositing filter is "multiply". The layer renders a solid gray
/// above 1.0 in extended linear sRGB, so the window server multiplies every
/// pixel beneath it into the extended range the panel reserves for HDR:
/// whites get brighter, blacks stay black, contrast is preserved. Showing
/// extended range content is also exactly what makes macOS engage the
/// panel's headroom, so the overlay bootstraps itself: it starts with a
/// small boost and ramps up as the reported headroom rises.
///
/// Everything is public API and macOS stays in charge of the panel: thermal
/// or power pressure can shrink the headroom at any time and the poll adapts.
/// The overlay dies with the app, so no display state can outlive a crash.
/// No windows, timers or observers exist while the feature is off.
final class ExtraBrightnessService: ObservableObject {
    static let shared = ExtraBrightnessService()

    /// A built-in display with EDR headroom exists (feature can work here).
    @Published private(set) var supported = false
    /// The boost is currently visible on the panel.
    @Published private(set) var boosting = false

    private var overlayWindow: NSWindow?
    private var overlayLayer: CAMetalLayer?
    /// A one-pixel corner window without the multiply filter. The multiply
    /// layer alone does not reliably make macOS engage the panel's headroom,
    /// but a plain extended range pixel does (verified on this hardware).
    /// Its layer keeps re-presenting on every poll tick: macOS only sustains
    /// the headroom while extended range content keeps being presented, and
    /// revokes it about a second after the last present (the boost visibly
    /// dropped out on XDR hardware when only the first frame was shown).
    private var triggerWindow: NSWindow?
    private var triggerLayer: CAMetalLayer?
    private var metalDevice: MTLDevice?
    private var commandQueue: MTLCommandQueue?
    private var pollTimer: Timer?
    private var screenObserver: NSObjectProtocol?
    private var sleepObservers: [NSObjectProtocol] = []
    /// While the screens sleep the compositor stops recycling drawables and
    /// nextDrawable would stall the main thread, so presents pause and a
    /// fresh render happens on wake.
    private var screensAsleep = false

    private init() {}

    func syncWithPreferences() {
        refreshSupported()
        let wanted = UserDefaults.standard.bool(forKey: DefaultsKey.extraBrightnessEnabled)
            && supported
        if wanted { start() } else { stop() }
    }

    /// Re-applies a level change immediately instead of waiting for the poll.
    func levelDidChange() {
        guard pollTimer != nil else { return }
        renderIfNeeded()
    }

    // MARK: - Detection

    /// The Mac's model identifier (for example Mac16,1), the primary signal
    /// for a real XDR panel: names and headroom values from NSScreen proved
    /// unreliable across machines and macOS versions.
    private static let modelIdentifier: String? = {
        var size = 0
        guard sysctlbyname("hw.model", nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname("hw.model", &buffer, &size, nil, 0) == 0 else { return nil }
        return String(cString: buffer)
    }()

    /// Which sustainable boost curve this panel generation takes.
    private static let panelReference = ExtraBrightnessSupport.panelReference(model: modelIdentifier)

    private static func builtInXDRScreen() -> NSScreen? {
        NSScreen.screens.first { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            else { return false }
            return CGDisplayIsBuiltin(number.uint32Value) != 0
                && ExtraBrightnessSupport.isSupportedPanel(
                    model: modelIdentifier,
                    localizedName: screen.localizedName,
                    potentialEDR: Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue))
        }
    }

    private func refreshSupported() {
        let now = Self.builtInXDRScreen() != nil
        if supported != now { supported = now }
    }

    // MARK: - Lifecycle

    private func start() {
        guard pollTimer == nil else { return }
        guard let screen = Self.builtInXDRScreen() else { return }
        showOverlay(on: screen)
        installObserver()
        // Four presents a second: the headroom grant follows recent extended
        // range presents and macOS revokes it about a second after they stop,
        // so this heartbeat keeps a comfortable margin while costing nothing.
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.renderIfNeeded()
        }
        pollTimer?.tolerance = 0.05
        renderIfNeeded()
    }

    func stop() {
        guard pollTimer != nil || overlayWindow != nil else { return }
        pollTimer?.invalidate()
        pollTimer = nil
        removeObserver()
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        triggerLayer = nil
        commandQueue = nil
        metalDevice = nil
        if boosting { boosting = false }
    }

    private func installObserver() {
        guard screenObserver == nil else { return }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main) { [weak self] _ in
            self?.handleScreenChange()
        }
        let workspace = NSWorkspace.shared.notificationCenter
        sleepObservers = [
            workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = true
            },
            workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification,
                                  object: nil, queue: .main) { [weak self] _ in
                self?.screensAsleep = false
                self?.renderIfNeeded()
            },
        ]
    }

    private func removeObserver() {
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        screenObserver = nil
        let workspace = NSWorkspace.shared.notificationCenter
        for observer in sleepObservers { workspace.removeObserver(observer) }
        sleepObservers = []
        screensAsleep = false
    }

    private func handleScreenChange() {
        refreshSupported()
        guard pollTimer != nil else { return }
        guard let screen = Self.builtInXDRScreen() else {
            // Built-in display gone (clamshell): release everything; the
            // preference stays on and a later screen change brings it back.
            stop()
            syncWithPreferences()
            return
        }
        showOverlay(on: screen)
        renderIfNeeded()
    }

    // MARK: - Overlay

    private func showOverlay(on screen: NSScreen) {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
        overlayLayer = nil

        let window = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        // Above regular windows and the menu bar so the whole picture is
        // boosted evenly; it ignores clicks, so it is never in the way.
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        // Screenshots and recordings must show the real content, not the
        // boosted composite (the overlay would wash captures out).
        window.sharingType = .none
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle,
                                     .fullScreenAuxiliary, .canJoinAllApplications]

        guard let device = MTLCreateSystemDefaultDevice(),
              let queue = device.makeCommandQueue() else { return }
        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.isOpaque = false
        // The window server multiplies everything beneath by this layer's
        // pixels. A uniform color needs no resolution: two by two is plenty.
        layer.compositingFilter = "multiply"
        layer.drawableSize = CGSize(width: 2, height: 2)
        layer.frame = CGRect(origin: .zero, size: screen.frame.size)

        let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        window.orderFrontRegardless()

        overlayWindow = window
        overlayLayer = layer
        metalDevice = device
        commandQueue = queue
        showTrigger(on: screen, device: device, queue: queue)
    }

    /// The one-pixel plain extended range window that makes macOS engage the
    /// panel's headroom (the multiply layer alone does not). It sits in the
    /// bottom right corner of the screen and is kept dim, so at most it reads
    /// as a faint dot there while the boost is on.
    private func showTrigger(on screen: NSScreen, device: MTLDevice, queue: MTLCommandQueue) {
        triggerWindow?.orderOut(nil)
        triggerWindow = nil
        triggerLayer = nil

        let frame = NSRect(x: screen.frame.maxX - 1, y: screen.frame.minY, width: 1, height: 1)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.animationBehavior = .none
        window.sharingType = .none
        window.collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle,
                                     .fullScreenAuxiliary, .canJoinAllApplications]

        let layer = CAMetalLayer()
        layer.device = device
        layer.pixelFormat = .rgba16Float
        layer.wantsExtendedDynamicRangeContent = true
        layer.colorspace = CGColorSpace(name: CGColorSpace.extendedLinearSRGB)
        layer.drawableSize = CGSize(width: 1, height: 1)
        layer.frame = CGRect(x: 0, y: 0, width: 1, height: 1)

        let view = NSView(frame: NSRect(x: 0, y: 0, width: 1, height: 1))
        view.wantsLayer = true
        view.layer = layer
        window.contentView = view
        window.orderFrontRegardless()
        triggerWindow = window
        triggerLayer = layer
        presentTrigger()
    }

    /// One clear pass of the extended range pixel. Called on every poll tick
    /// while the boost is on: the headroom grant follows recent presents, so
    /// a single frame engages it only to lose it a moment later.
    private func presentTrigger() {
        guard let layer = triggerLayer,
              let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        // Comfortably in extended range so the headroom engages, but dim
        // enough that the single pixel stays unobtrusive.
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 1.8, green: 1.8, blue: 1.8, alpha: 1.0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
    }

    /// Renders the multiply color for the current level and headroom, every
    /// poll tick. Both layers keep presenting for as long as the boost is on:
    /// macOS grants the panel's headroom in response to presented extended
    /// range content and revokes it moments after presents stop, which
    /// visibly dropped the boost after a second on XDR hardware. Two tiny
    /// clear passes per tick cost nothing measurable.
    private func renderIfNeeded() {
        guard !screensAsleep else { return }
        guard let screen = Self.builtInXDRScreen(), overlayLayer != nil else { return }
        presentTrigger()
        let level = Double(UserDefaults.standard.integer(forKey: DefaultsKey.extraBrightnessLevel)) / 100.0
        let headroom = Double(screen.maximumExtendedDynamicRangeColorComponentValue)
        let potential = Double(screen.maximumPotentialExtendedDynamicRangeColorComponentValue)
        let factor = ExtraBrightnessSupport.renderFactor(level: level, currentEDR: headroom,
                                                         potentialEDR: potential,
                                                         reference: Self.panelReference)
        render(factor: factor)
    }

    /// One clear-only render pass, no shaders: the drawable is a uniform gray
    /// at `factor`, which the compositing filter multiplies with the screen.
    private func render(factor: Double) {
        guard let layer = overlayLayer,
              let queue = commandQueue,
              let drawable = layer.nextDrawable(),
              let commands = queue.makeCommandBuffer() else { return }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: factor, green: factor,
                                                            blue: factor, alpha: 1.0)
        guard let encoder = commands.makeRenderCommandEncoder(descriptor: pass) else { return }
        encoder.endEncoding()
        commands.present(drawable)
        commands.commit()
        let visible = factor > 1.001
        if boosting != visible { boosting = visible }
    }
}

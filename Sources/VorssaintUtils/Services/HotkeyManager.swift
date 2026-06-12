import Carbon.HIToolbox
import Foundation

/// Global ⌃⌥⌘K shortcut via Carbon (no Accessibility permission required).
final class HotkeyManager {
    static let shared = HotkeyManager()

    var onActivate: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    private init() {}

    func setEnabled(_ enabled: Bool) {
        enabled ? register() : unregister()
    }

    private func register() {
        guard hotKeyRef == nil else { return }
        if eventHandler == nil {
            var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                     eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetEventDispatcherTarget(), { _, _, userData -> OSStatus in
                guard let userData else { return noErr }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async { manager.onActivate?() }
                return noErr
            }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &eventHandler)
        }
        let hotKeyID = EventHotKeyID(signature: 0x5655_544C, id: 1) // 'VUTL'
        RegisterEventHotKey(UInt32(kVK_ANSI_K),
                            UInt32(controlKey | optionKey | cmdKey),
                            hotKeyID,
                            GetEventDispatcherTarget(),
                            0,
                            &hotKeyRef)
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
    }
}

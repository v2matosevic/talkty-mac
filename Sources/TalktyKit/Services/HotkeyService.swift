import Foundation
import Carbon.HIToolbox

/// Global hotkey registration via the Carbon Event Manager (RegisterEventHotKey).
/// Chosen over a CGEvent tap because it works system-wide WITHOUT Accessibility
/// permission and cleanly consumes the key. ESC-to-cancel is registered only while
/// recording. Replaces the Win32 RegisterHotKey + WM_HOTKEY message pump.
public final class HotkeyService {
    /// Hotkey key-down (leading edge). Toggle mode: toggles recording. Push-to-talk: starts it.
    public var onKeyDown: (() -> Void)?
    /// Hotkey key-up — only used in push-to-talk mode (to stop).
    public var onKeyUp: (() -> Void)?
    public var onCancel: (() -> Void)?

    /// Hold-to-talk: report key-down/up edges instead of debounced toggles.
    public var pushToTalk = false { didSet { held = false } }
    private var held = false

    private var toggleRef: EventHotKeyRef?
    private var cancelRef: EventHotKeyRef?
    private var handlerInstalled = false
    private var lastToggle = Date.distantPast

    private static let toggleID: UInt32 = 0x544B5901   // 'TKY\x01'
    private static let cancelID: UInt32 = 0x544B5902

    public init() {}

    /// Install the shared Carbon event handler once.
    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        // Listen for both press AND release so push-to-talk can stop on key-up.
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, userData in
            guard let event, let userData else { return noErr }
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
            service.handle(id: hkID.id, kind: GetEventKind(event))
            return noErr
        }, 2, &specs, selfPtr, nil)
        handlerInstalled = true
    }

    private func handle(id: UInt32, kind: UInt32) {
        if id == Self.toggleID {
            if kind == UInt32(kEventHotKeyPressed) {
                if pushToTalk {
                    guard !held else { return }   // leading edge only (no auto-repeat)
                    held = true
                    Log.debug("Hotkey: key-down (push-to-talk)")
                    onKeyDown?()
                } else {
                    // Toggle: debounce (Constants.hotkeyDebounce) to swallow double-fires.
                    let now = Date()
                    if now.timeIntervalSince(lastToggle) < Constants.hotkeyDebounce {
                        Log.debug("Hotkey toggle debounced"); return
                    }
                    lastToggle = now
                    Log.debug("Hotkey: toggle fired")
                    onKeyDown?()
                }
            } else if kind == UInt32(kEventHotKeyReleased) {
                guard pushToTalk, held else { return }
                held = false
                Log.debug("Hotkey: key-up (push-to-talk)")
                onKeyUp?()
            }
        } else if id == Self.cancelID, kind == UInt32(kEventHotKeyPressed) {
            Log.debug("Hotkey: cancel (ESC) fired")
            onCancel?()
        }
    }

    @discardableResult
    public func registerToggle(_ config: HotkeyConfig) -> Bool {
        installHandlerIfNeeded()
        unregisterToggle()
        held = false
        guard config.isValid else { return false }
        let id = EventHotKeyID(signature: OSType(0x544B5953), id: Self.toggleID)  // 'TKYS'
        let status = RegisterEventHotKey(config.keyCode, carbonModifiers(config.modifiers),
                                         id, GetEventDispatcherTarget(), 0, &toggleRef)
        if status == noErr { Log.info("Hotkey registered: \(config.displayString)") }
        else { Log.warning("RegisterEventHotKey failed (\(status)) for \(config.displayString)") }
        return status == noErr
    }

    public func unregisterToggle() {
        if let toggleRef { UnregisterEventHotKey(toggleRef) }
        toggleRef = nil
    }

    /// Register ESC (keyCode 53) as a no-modifier cancel hotkey while recording.
    public func registerCancel() {
        installHandlerIfNeeded()
        unregisterCancel()
        let id = EventHotKeyID(signature: OSType(0x544B5943), id: Self.cancelID)  // 'TKYC'
        RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetEventDispatcherTarget(), 0, &cancelRef)
    }

    public func unregisterCancel() {
        if let cancelRef { UnregisterEventHotKey(cancelRef) }
        cancelRef = nil
    }

    private func carbonModifiers(_ m: HotkeyModifiers) -> UInt32 {
        var c: UInt32 = 0
        if m.contains(.command) { c |= UInt32(cmdKey) }
        if m.contains(.option)  { c |= UInt32(optionKey) }
        if m.contains(.control) { c |= UInt32(controlKey) }
        if m.contains(.shift)   { c |= UInt32(shiftKey) }
        return c
    }
}

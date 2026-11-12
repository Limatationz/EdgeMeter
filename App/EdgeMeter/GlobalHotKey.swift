import Carbon.HIToolbox

/// A system-wide shortcut via Carbon's `RegisterEventHotKey` (FEATURES.md 3.2, 17).
///
/// `NSEvent.addGlobalMonitorForEvents` can only observe keys, not consume them, and
/// needs Accessibility permission. Carbon hot keys need neither and still work on
/// current macOS.
@MainActor
final class GlobalHotKey {
    private static var registry: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1
    private static var handlerInstalled = false

    private let id: UInt32
    private var ref: EventHotKeyRef?
    private let action: () -> Void

    /// - Parameters:
    ///   - keyCode: virtual key code, e.g. `kVK_ANSI_M`.
    ///   - modifiers: Carbon modifier mask, e.g. `cmdKey | optionKey | controlKey`.
    init?(keyCode: Int, modifiers: Int, action: @escaping () -> Void) {
        id = Self.nextID
        Self.nextID += 1
        self.action = action
        Self.installHandlerIfNeeded()
        let hotKeyID = EventHotKeyID(signature: OSType(0x4544_474D), id: id) // 'EDGM'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(modifiers), hotKeyID, GetEventDispatcherTarget(), 0, &ref)
        guard status == noErr else { return nil }
        Self.registry[id] = self
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        Self.registry[id] = nil
    }

    private static func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetEventDispatcherTarget(), { _, event, _ -> OSStatus in
            guard let event else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard status == noErr else { return status }
            let id = hotKeyID.id
            // Carbon delivers hot-key events on the main thread's event loop.
            MainActor.assumeIsolated { GlobalHotKey.registry[id]?.action() }
            return noErr
        }, 1, &spec, nil, nil)
        handlerInstalled = true
    }
}

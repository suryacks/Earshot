import AppKit
import Carbon.HIToolbox

/// A system-wide keyboard shortcut.
///
/// Uses Carbon's `RegisterEventHotKey` rather than an `NSEvent` global monitor
/// because Carbon hot keys need no Accessibility permission - asking for input
/// monitoring just to open a battery popover would be a hard sell.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: () -> Void
    private static var instances: [UInt32: GlobalHotKey] = [:]
    private static var nextID: UInt32 = 1

    /// Default: ⌥⌘E.
    init?(keyCode: UInt32 = UInt32(kVK_ANSI_E),
          modifiers: UInt32 = UInt32(optionKey | cmdKey),
          action: @escaping () -> Void) {
        self.action = action

        let id = Self.nextID
        Self.nextID += 1
        Self.instances[id] = self

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, _ -> OSStatus in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            GlobalHotKey.instances[hotKeyID.id]?.action()
            return noErr
        }, 1, &eventType, nil, &handler)
        guard status == noErr else { Self.instances[id] = nil; return nil }

        let hotKeyID = EventHotKeyID(signature: OSType(0x45415253), id: id)  // 'EARS'
        let registered = RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                                             GetApplicationEventTarget(), 0, &ref)
        guard registered == noErr else { Self.instances[id] = nil; return nil }
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}

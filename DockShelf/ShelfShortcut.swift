import AppKit
import Carbon

/// Registers one explicit shortcut; does not observe arbitrary keystrokes.
@MainActor
final class ShelfShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let action: @MainActor () -> Void
    private(set) var registrationStatus: OSStatus = OSStatus(eventInternalErr)
    var isRegistered: Bool { registrationStatus == noErr }

    init(action: @escaping @MainActor () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var identifier = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
            guard status == noErr, identifier.signature == 0x44534846, identifier.id == 1 else {
                return OSStatus(eventNotHandledErr)
            }
            let shortcut = Unmanaged<ShelfShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action() }
            return noErr
        }, 1, &eventType, context, &handler)
        guard installed == noErr else {
            registrationStatus = installed
            return
        }
        registrationStatus = RegisterEventHotKey(
            UInt32(kVK_Space), UInt32(controlKey | optionKey),
            EventHotKeyID(signature: 0x44534846, id: 1),
            GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &hotKey
        )
        if !isRegistered, let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

import AppKit
import Carbon

@MainActor
private final class FakeShortcutDriver: ShelfShortcutDriver {
    var action: (() -> Void)?
    var registrations: [ShelfShortcutBinding] = []
    var registerResults: [OSStatus] = []
    var unregisterResults: [OSStatus] = []
    var active: ShelfShortcutBinding?
    func register(_ binding: ShelfShortcutBinding) -> OSStatus {
        registrations.append(binding)
        let result = registerResults.isEmpty ? noErr : registerResults.removeFirst()
        if result == noErr { active = binding }
        return result
    }
    func unregister() -> OSStatus {
        let result = unregisterResults.isEmpty ? noErr : unregisterResults.removeFirst()
        if result == noErr { active = nil }
        return result
    }
}

@main
struct ShelfShortcutSmoke {
    @MainActor
    static func main() throws {
        let suite = "DockShelfShortcutSmoke.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let storage = ShelfShortcutStorage.preferences(defaults)
        let other = ShelfShortcutBinding(keyCode: UInt32(kVK_ANSI_K), modifiers: UInt32(cmdKey | shiftKey), keyLabel: "K")
        var triggered = 0
        let driver = FakeShortcutDriver()
        let model = ShelfShortcut(storage: storage, driver: driver) { triggered += 1 }
        check(model.configuration == .standard && model.isRegistered, "default registers without writing a preference")
        check(defaults.object(forKey: ShelfShortcutStorage.key) == nil, "first launch preserves absence of preference")
        driver.action?()
        check(triggered == 1, "registered hotkey reaches action")
        model.beginRecording()
        check(model.isRecording && !model.isRegistered && driver.active == nil, "recording releases global key so it can be captured locally")
        driver.action?()
        check(triggered == 1, "queued action cannot toggle shelf while recording")
        model.rejectRecording()
        check(model.isRecording && model.notice != nil, "plain keys leave recorder open with explicit instructions")
        model.cancelRecording()
        check(!model.isRecording && model.isRegistered && model.configuration == .standard, "Escape or losing window restores original registration")
        model.beginRecording()
        model.apply(other)
        check(model.configuration == other && model.activeConfiguration == other && !model.isRecording, "valid recording applies immediately")
        check((try storage.load()) == other, "configured key survives preferences round trip")
        let reopened = ShelfShortcut(storage: storage, driver: FakeShortcutDriver(), action: {})
        check(reopened.configuration == other && reopened.isRegistered, "restart reloads custom key")
        reopened.stop()

        driver.registerResults = [OSStatus(eventHotKeyExistsErr), noErr]
        model.beginRecording()
        model.apply(.standard)
        check(model.configuration == other && model.activeConfiguration == other, "conflict preserves and restores previous combination")
        check(model.notice?.contains("占用") == true && model.statusText.contains(other.display), "conflict stays visible alongside actual active key")
        check((try storage.load()) == other, "conflict never overwrites preference")
        driver.registerResults = [OSStatus(eventHotKeyExistsErr), OSStatus(eventInternalErr)]
        model.apply(.standard)
        check(!model.isRegistered && model.statusText.contains("也未恢复"), "failed rollback remains unavailable rather than fake success")
        model.retryRegistration()
        check(model.isRegistered && model.notice == nil, "explicit retry re-enables saved combination")
        driver.unregisterResults = [OSStatus(eventInternalErr)]
        model.beginRecording()
        check(!model.isRecording && model.activeConfiguration == other && model.notice != nil, "failed release cannot start recorder or hide active key")
        model.apply(.standard)
        check((try storage.load()) == .standard && model.configuration == .standard, "restore default uses same checked save path")
        model.stop()
        driver.action?()
        check(!model.isRegistered && !model.statusText.contains("已启用") && triggered == 1, "stop unregisters and disconnects action")

        let saveDriver = FakeShortcutDriver()
        var saveFails = true
        let failingStorage = ShelfShortcutStorage(load: { .standard }, save: { _ in
            if saveFails { throw CocoaError(.fileWriteNoPermission) }
        })
        let saveModel = ShelfShortcut(storage: failingStorage, driver: saveDriver, action: {})
        saveModel.apply(other)
        check(saveModel.configuration == .standard && saveModel.activeConfiguration == .standard && saveModel.notice?.contains("未保存") == true, "save failure restores previous live key and remains visible")
        saveFails = false
        saveModel.apply(other)
        check(saveModel.configuration == other && saveModel.notice == nil, "retry can persist and clear save error")
        saveModel.stop()

        defaults.set(Data("broken".utf8), forKey: ShelfShortcutStorage.key)
        let corrupt = ShelfShortcut(storage: storage, driver: FakeShortcutDriver(), action: {})
        check(corrupt.configuration == .standard && corrupt.preferenceProblem != nil, "corrupt settings explicitly marked while default used")
        corrupt.beginRecording(); corrupt.cancelRecording()
        check(corrupt.preferenceProblem != nil && defaults.data(forKey: ShelfShortcutStorage.key) == Data("broken".utf8), "cancel preserves unreadable original and warning")
        corrupt.apply(.standard)
        check((try storage.load()) == .standard && corrupt.preferenceProblem == nil, "explicit setting repairs invalid preference")
        corrupt.stop()

        // Construct event values for parsing only; never send keyboard input to an app.
        let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [.control, .option], timestamp: 0, windowNumber: 0, context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49)!
        check(ShelfShortcutBinding.capture(event) == .standard, "recorder converts event modifiers and named space key to global binding")
        let plain = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
        check(ShelfShortcutBinding.capture(plain) == nil, "local recorder rejects ordinary typing")

        let invalid = ShelfShortcutBinding(keyCode: 0, modifiers: 0, keyLabel: "A")
        check(!invalid.isValid, "unmodified typing cannot become a global shortcut")
        check(!ShelfShortcutBinding(keyCode: 55, modifiers: UInt32(cmdKey), keyLabel: "Command").isValid, "modifier-only shortcut is rejected")
        check(!ShelfShortcutBinding(keyCode: 53, modifiers: UInt32(cmdKey), keyLabel: "Esc").isValid, "Escape always remains cancellation")
        let key = [kHISymbolicHotKeyEnabled as String: NSNumber(value: true), kHISymbolicHotKeyCode as String: NSNumber(value: other.keyCode), kHISymbolicHotKeyModifiers as String: NSNumber(value: other.modifiers)]
        check(CarbonShelfShortcutDriver.conflictsWithSystemShortcut(other, keys: [key]), "enabled system shortcut blocks false successful registration")
        var disabled = key; disabled[kHISymbolicHotKeyEnabled as String] = NSNumber(value: false)
        check(!CarbonShelfShortcutDriver.conflictsWithSystemShortcut(other, keys: [disabled]), "disabled system shortcut is not a conflict")

        try nativeEventDispatch()
        print("ShelfShortcutSmoke passed: settings, recording, conflict, rollback, persistence failure, reserved keys and native event dispatch")
    }

    @MainActor
    static func nativeEventDispatch() throws {
        // No app/window launch and no generated keyboard input. Send a Carbon
        // notification directly to our handler, whose action only increments a counter.
        let driver = CarbonShelfShortcutDriver()
        let key = ShelfShortcutBinding(keyCode: UInt32(kVK_F20), modifiers: UInt32(controlKey | optionKey | cmdKey | shiftKey), keyLabel: "F20")
        let status = driver.register(key)
        check(status == noErr, "native registration succeeds for test combination (OSStatus \(status))")
        defer { _ = driver.unregister() }
        var fired = 0
        driver.action = { fired += 1 }
        func send(signature: OSType, id: UInt32) -> OSStatus {
            var event: EventRef?
            let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0, EventAttributes(kEventAttributeNone), &event)
            guard created == noErr, let event else { return created }
            defer { ReleaseEvent(event) }
            var identifier = EventHotKeyID(signature: signature, id: id)
            let parameter = SetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &identifier)
            guard parameter == noErr else { return parameter }
            return SendEventToEventTarget(event, GetEventDispatcherTarget())
        }
        check(send(signature: CarbonShelfShortcutDriver.signature, id: driver.identifier) == noErr && fired == 1, "Carbon dispatcher delivers parsed hotkey notification to action")
        _ = send(signature: 0x11111111, id: driver.identifier)
        _ = send(signature: CarbonShelfShortcutDriver.signature, id: driver.identifier &+ 1)
        check(fired == 1, "unrelated and stale hotkey identifiers do not trigger action")
        let duplicate = CarbonShelfShortcutDriver()
        check(duplicate.register(key) == OSStatus(eventHotKeyExistsErr), "native duplicate registration returns explicit conflict")
        check(driver.unregister() == noErr, "native unregister releases combination")
        _ = send(signature: CarbonShelfShortcutDriver.signature, id: driver.identifier)
        check(fired == 1, "released registration cannot deliver queued notification")
    }

    private static func check(_ condition: Bool, _ message: String) {
        if !condition { fatalError(message) }
    }
}

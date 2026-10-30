import AppKit
import Carbon
import Combine

struct ShelfShortcutBinding: Codable, Equatable {
    let keyCode: UInt32
    let modifiers: UInt32
    let keyLabel: String

    static let standard = Self(keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey), keyLabel: "Space")
    static let modifierMask = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    private static let modifierKeys: Set<UInt32> = [54, 55, 56, 57, 58, 59, 60, 61, 62, 63]
    var isValid: Bool {
        keyCode < 128 && !Self.modifierKeys.contains(keyCode) && keyCode != UInt32(kVK_Escape) &&
        modifiers & ~Self.modifierMask == 0 && modifiers & UInt32(controlKey | optionKey | cmdKey) != 0 &&
        !keyLabel.isEmpty && keyLabel.count <= 24 && !keyLabel.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
    }
    var display: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + " " + keyLabel
    }
    var accessibilityLabel: String {
        [modifiers & UInt32(controlKey) != 0 ? "Control" : nil,
         modifiers & UInt32(optionKey) != 0 ? "Option" : nil,
         modifiers & UInt32(shiftKey) != 0 ? "Shift" : nil,
         modifiers & UInt32(cmdKey) != 0 ? "Command" : nil,
         keyLabel == "Space" ? "空格" : keyLabel].compactMap { $0 }.joined(separator: "、")
    }
    static func capture(_ event: NSEvent) -> Self? {
        let flags = event.modifierFlags
        var modifiers: UInt32 = 0
        if flags.contains(.control) { modifiers |= UInt32(controlKey) }
        if flags.contains(.option) { modifiers |= UInt32(optionKey) }
        if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
        if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
        let named: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 117: "⌦", 123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down", 76: "Enter", 122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12", 105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19", 90: "F20"]
        guard let label = named[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased(), !label.isEmpty else { return nil }
        let binding = Self(keyCode: UInt32(event.keyCode), modifiers: modifiers, keyLabel: label)
        return binding.isValid ? binding : nil
    }
}

struct ShelfShortcutStorage {
    var load: () throws -> ShelfShortcutBinding?
    var save: (ShelfShortcutBinding) throws -> Void
    static let key = "DockShelf.shortcut.v1"
    static func preferences(_ defaults: UserDefaults) -> Self {
        Self(load: {
            guard let object = defaults.object(forKey: key) else { return nil }
            guard let data = object as? Data else { throw CocoaError(.coderReadCorrupt) }
            let binding = try JSONDecoder().decode(ShelfShortcutBinding.self, from: data)
            guard binding.isValid else { throw CocoaError(.coderReadCorrupt) }
            return binding
        }, save: { binding in
            let data = try JSONEncoder().encode(binding)
            defaults.set(data, forKey: key)
            guard defaults.data(forKey: key) == data else { throw CocoaError(.fileWriteUnknown) }
        })
    }
}

@MainActor
protocol ShelfShortcutDriver: AnyObject {
    var action: (() -> Void)? { get set }
    func register(_ binding: ShelfShortcutBinding) -> OSStatus
    func unregister() -> OSStatus
}

/// Only one explicit global hotkey; recording is handled locally by the help panel.
@MainActor
final class CarbonShelfShortcutDriver: ShelfShortcutDriver {
    static let signature: OSType = 0x44534846
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private(set) var identifier: UInt32 = 0
    var action: (() -> Void)?

    func register(_ binding: ShelfShortcutBinding) -> OSStatus {
        guard hotKey == nil else { return OSStatus(eventHotKeyExistsErr) }
        var systemKeys: Unmanaged<CFArray>?
        let queryStatus = CopySymbolicHotKeys(&systemKeys)
        guard queryStatus == noErr else { return queryStatus }
        guard let keys = systemKeys?.takeRetainedValue() as? [[String: Any]] else { return OSStatus(eventInternalErr) }
        if Self.conflictsWithSystemShortcut(binding, keys: keys) { return OSStatus(eventHotKeyExistsErr) }
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            let status = InstallEventHandler(GetEventDispatcherTarget(), { _, event, context in
                guard let event, let context else { return OSStatus(eventNotHandledErr) }
                var identifier = EventHotKeyID()
                let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &identifier)
                guard status == noErr else { return status }
                let driver = Unmanaged<CarbonShelfShortcutDriver>.fromOpaque(context).takeUnretainedValue()
                return MainActor.assumeIsolated { driver.deliver(identifier) }
            }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
            guard status == noErr else { return status }
        }
        // Dispatcher target receives hotkey events before AppKit's key-equivalent handling.
        // Use a fresh ID so a queued event from a replaced registration is ignored.
        identifier &+= 1
        return RegisterEventHotKey(binding.keyCode, binding.modifiers,
            EventHotKeyID(signature: Self.signature, id: identifier), GetEventDispatcherTarget(),
            OptionBits(kEventHotKeyExclusive), &hotKey)
    }

    static func conflictsWithSystemShortcut(_ binding: ShelfShortcutBinding, keys: [[String: Any]]) -> Bool {
        keys.contains { key in
            (key[kHISymbolicHotKeyEnabled as String] as? NSNumber)?.boolValue == true &&
            (key[kHISymbolicHotKeyCode as String] as? NSNumber)?.uint32Value == binding.keyCode &&
            (key[kHISymbolicHotKeyModifiers as String] as? NSNumber)?.uint32Value == binding.modifiers
        }
    }

    func deliver(_ identifier: EventHotKeyID) -> OSStatus {
        guard hotKey != nil, identifier.signature == Self.signature, identifier.id == self.identifier else {
            return OSStatus(eventNotHandledErr)
        }
        action?()
        return noErr
    }

    func unregister() -> OSStatus {
        guard let hotKey else { return noErr }
        let status = UnregisterEventHotKey(hotKey)
        if status == noErr { self.hotKey = nil }
        return status
    }
    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}

@MainActor
final class ShelfShortcut: ObservableObject {
    @Published private(set) var configuration: ShelfShortcutBinding = .standard
    @Published private(set) var activeConfiguration: ShelfShortcutBinding?
    @Published private(set) var isRecording = false
    @Published private(set) var notice: String?
    @Published private(set) var preferenceProblem: String?
    private(set) var registrationStatus: OSStatus = OSStatus(eventInternalErr)
    private let storage: ShelfShortcutStorage
    private let driver: any ShelfShortcutDriver
    var isRegistered: Bool { activeConfiguration != nil && !isRecording }
    var hasProblem: Bool { notice != nil || preferenceProblem != nil || !isRegistered }
    var statusText: String {
        if isRecording { return notice ?? "请按新组合键，至少包含 Control、Option 或 Command；Esc 取消。" }
        let warning = notice ?? preferenceProblem
        let active = activeConfiguration.map { "当前生效：\($0.display)。" } ?? "快捷键未启用。"
        return warning.map { $0 + " " + active } ?? (isRegistered ? "已启用，可在其他应用中打开或收起搁板。" : "快捷键未启用。")
    }

    init(storage: ShelfShortcutStorage = .preferences(.standard), driver: (any ShelfShortcutDriver)? = nil,
         action: @escaping @MainActor () -> Void) {
        self.storage = storage
        self.driver = driver ?? CarbonShelfShortcutDriver()
        do { configuration = try storage.load() ?? .standard }
        catch { preferenceProblem = "已保存的快捷键无法读取，暂用默认组合；请重新设置。" }
        self.driver.action = { [weak self] in
            guard let self, self.isRegistered else { return }
            action()
        }
        activate(configuration)
    }

    func beginRecording() {
        guard !isRecording, deactivate() else { return }
        notice = nil
        isRecording = true
    }
    func rejectRecording() { notice = "请同时按住 Control、Option 或 Command；Esc 取消。" }
    func cancelRecording() {
        guard isRecording else { return }
        isRecording = false
        notice = nil
        activate(configuration)
    }
    func apply(_ binding: ShelfShortcutBinding) {
        guard binding.isValid else {
            notice = "组合键无效，请至少包含 Control、Option 或 Command。"
            return
        }
        guard deactivate() else { return }
        isRecording = false
        notice = nil
        activate(binding)
        guard activeConfiguration == binding else {
            let failure = notice ?? "无法注册新快捷键。"
            restorePrevious(after: failure)
            return
        }
        do {
            try storage.save(binding)
            configuration = binding
            preferenceProblem = nil
        } catch {
            let failure = "新快捷键未保存，请重试。"
            if deactivate() { restorePrevious(after: failure) }
            else { notice = failure + " 新组合仍生效，但重启不会保留；请重试。" }
        }
    }
    func retryRegistration() {
        guard !isRecording, deactivate() else { return }
        notice = nil
        activate(configuration)
    }
    func stop() {
        isRecording = false
        _ = deactivate()
        driver.action = nil
    }
    private func activate(_ binding: ShelfShortcutBinding) {
        registrationStatus = driver.register(binding)
        if registrationStatus == noErr { activeConfiguration = binding }
        else if registrationStatus == OSStatus(eventHotKeyExistsErr) {
            notice = "该组合键已被系统或其他应用占用，请换一个组合；也可退出占用它的应用后重试。"
        } else { notice = "快捷键注册失败（\(registrationStatus)），请重试或修改组合。" }
    }
    private func deactivate() -> Bool {
        let status = driver.unregister()
        guard status == noErr else {
            notice = "无法释放当前快捷键（\(status)），请重试。"
            return false
        }
        activeConfiguration = nil
        return true
    }
    private func restorePrevious(after failure: String) {
        activate(configuration)
        notice = activeConfiguration == nil ? failure + " 原快捷键也未恢复（\(registrationStatus)），请重试。" : failure
    }
}

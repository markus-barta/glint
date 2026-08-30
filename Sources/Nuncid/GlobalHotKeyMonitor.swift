import AppKit
import Carbon

private let nuncidHotKeySignature: OSType = 0x4E554E43 // NUNC

private func nuncidHotKeyHandler(_: EventHandlerCallRef?, event: EventRef?, userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var identifier = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &identifier
    )
    guard status == noErr, identifier.signature == nuncidHotKeySignature else { return OSStatus(eventNotHandledErr) }
    let monitor = Unmanaged<GlobalHotKeyMonitor>.fromOpaque(userData).takeUnretainedValue()
    Task { @MainActor in monitor.invoke(id: identifier.id) }
    return noErr
}

@MainActor final class GlobalHotKeyMonitor {
    enum Command: UInt32, CaseIterable { case inspect = 1, pin = 2 }

    var onCommand: ((Command) -> Void)?
    private(set) var errors: [Command: String] = [:]
    private var references: [Command: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    init() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(
            GetApplicationEventTarget(),
            nuncidHotKeyHandler,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &handler
        )
    }

    deinit {
        references.values.forEach { _ = UnregisterEventHotKey($0) }
        if let handler { RemoveEventHandler(handler) }
    }

    func configure(inspect: HotKey?, pin: HotKey?) {
        references.values.forEach { _ = UnregisterEventHotKey($0) }
        references.removeAll()
        errors.removeAll()
        register(inspect, command: .inspect)
        register(pin, command: .pin)
    }

    fileprivate func invoke(id: UInt32) {
        guard let command = Command(rawValue: id) else { return }
        onCommand?(command)
    }

    private func register(_ hotKey: HotKey?, command: Command) {
        guard let hotKey else { return }
        var reference: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: nuncidHotKeySignature, id: command.rawValue)
        let status = RegisterEventHotKey(
            hotKey.keyCode,
            carbonModifiers(hotKey.modifiers),
            identifier,
            GetApplicationEventTarget(),
            0,
            &reference
        )
        if status == noErr, let reference {
            references[command] = reference
        } else {
            errors[command] = "macOS could not register \(hotKey.label) (error \(status))."
        }
    }

    private func carbonModifiers(_ modifiers: HotKeyModifiers) -> UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }
}

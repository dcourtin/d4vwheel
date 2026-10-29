import Carbon.HIToolbox

/// Raccourci clavier global (Carbon `RegisterEventHotKey`) : pas besoin d'autorisation Accessibilité.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    /// Par défaut : Contrôle + Option + Espace.
    static let defaultKeyCode = UInt32(kVK_Space)
    static let defaultModifiers = UInt32(controlKey | optionKey)
    static let defaultDescription = "⌃⌥␣"

    /// Raccourci d'après les réglages.
    convenience init?(spec: Triggers.HotKeySpec, action: @escaping () -> Void) {
        self.init(keyCode: spec.keyCode, modifiers: spec.modifiers, action: action)
    }

    init?(keyCode: UInt32 = GlobalHotKey.defaultKeyCode,
          modifiers: UInt32 = GlobalHotKey.defaultModifiers,
          action: @escaping () -> Void) {
        self.action = action
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let installed = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return noErr }
            Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action()
            return noErr
        }, 1, &spec, selfPtr, &handlerRef)
        guard installed == noErr else { return nil }
        let id = EventHotKeyID(signature: 0x44345657 /* 'D4VW' */, id: 1)
        let registered = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        guard registered == noErr else {
            if let handlerRef { RemoveEventHandler(handlerRef) }
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

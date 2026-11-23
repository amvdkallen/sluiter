import AppKit
import Carbon.HIToolbox

// MARK: - Globale sneltoets (werkt ook als Sluiter niet actief is)

final class HotKey {
    static let shared = HotKey()

    var action: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?

    private init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { HotKey.shared.action?() }
            return noErr
        }, 1, &spec, nil, &handlerRef)
    }

    /// (Her)registreert de sneltoets. Geeft false als een andere app hem al gebruikt.
    @discardableResult
    func register(keyCode: Int, carbonModifiers: Int) -> Bool {
        unregister()
        let id = EventHotKeyID(signature: OSType(0x534C5452), id: 1) // 'SLTR'
        let status = RegisterEventHotKey(UInt32(keyCode), UInt32(carbonModifiers), id,
                                         GetApplicationEventTarget(), 0, &ref)
        return status == noErr
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
    }

    // MARK: Hulpjes voor weergave en omrekenen

    static func carbonModifiers(from flags: NSEvent.ModifierFlags) -> Int {
        var m = 0
        if flags.contains(.command) { m |= cmdKey }
        if flags.contains(.option) { m |= optionKey }
        if flags.contains(.control) { m |= controlKey }
        if flags.contains(.shift) { m |= shiftKey }
        return m
    }

    static func describe(keyCode: Int, carbonModifiers m: Int, characters: String?) -> String {
        var s = ""
        if m & controlKey != 0 { s += "⌃" }
        if m & optionKey != 0 { s += "⌥" }
        if m & shiftKey != 0 { s += "⇧" }
        if m & cmdKey != 0 { s += "⌘" }
        let special: [Int: String] = [
            kVK_Space: "Spatie", kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Escape: "esc", kVK_Delete: "⌫",
            kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
            kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
            kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        return s + (special[keyCode] ?? (characters ?? "?").uppercased())
    }
}

import Carbon
import AppKit

/// Registers a global keyboard shortcut via Carbon RegisterEventHotKey.
final class HotkeyManager {
    static let shared = HotkeyManager()
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private(set) var currentSignature: String = ""

    // Default: Option+Return
    private(set) var keyCode: UInt32 = UInt32(kVK_Return)
    private(set) var modifiers: UInt32 = UInt32(optionKey)
    var unregisterForRecording: Bool = false {
        didSet {
            if unregisterForRecording {
                unregister()
            } else {
                register()
            }
        }
    }

    init() {
        register()
    }

    func updateShortcut(keyCode: UInt32, modifiers: UInt32) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        register()
    }

    func updateShortcut(fromString s: String) {
        // Parse "⌥⏎" style strings — maps symbol chars to key codes
        var mods: UInt32 = 0
        var kc: UInt32 = UInt32(kVK_Return)
        for ch in s {
            switch ch {
            case "⌘": mods |= UInt32(cmdKey)
            case "⌥": mods |= UInt32(optionKey)
            case "⇧": mods |= UInt32(shiftKey)
            case "⌃": mods |= UInt32(controlKey)
            case "⏎": kc = UInt32(kVK_Return)
            case "␣": kc = UInt32(kVK_Space)
            default:
                if let ascii = ch.asciiValue, ascii >= 0x20 {
                    kc = UInt32(ascii - 36) // rough ASCII→virtual key mapping
                }
            }
        }
        // Reset to defaults if parse failed
        if kc == 0 { kc = UInt32(kVK_Return) }
        updateShortcut(keyCode: kc, modifiers: mods)
    }

    private func register() {
        unregister()

        var eventType = EventTypeSpec()
        eventType.eventClass = OSType(kEventClassKeyboard)
        eventType.eventKind = UInt32(kEventHotKeyPressed)

        let handler: EventHandlerUPP = { _, event, userData in
            // The hotkey was pressed — trigger capture+solve
            DispatchQueue.main.async {
                CaptureCoordinator.shared.triggerCaptureAndSolve()
            }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            handler,
            1,
            &eventType,
            nil,
            &eventHandler
        )

        let signature = OSType(0x4F525552) // 'ORUR'
        var hotKeyID = EventHotKeyID(signature: signature, id: 1)

        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        currentSignature = "registered"
        NSLog("[OpenRubric] Global shortcut installed (keyCode=\(keyCode), mods=\(modifiers))")
    }

    private func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregister()
    }
}

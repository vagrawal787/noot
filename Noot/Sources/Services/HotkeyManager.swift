import Cocoa
import Carbon
import ApplicationServices

final class HotkeyManager {
    static let shared = HotkeyManager()

    private var eventHandler: EventHandlerRef?
    private var hotkeys: [UInt32: () -> Void] = [:]
    private var nextHotkeyId: UInt32 = 1

    private init() {}

    func register() {
        // Check if we have accessibility permissions (required for global hotkeys)
        let trusted = AXIsProcessTrusted()
        print("Accessibility permissions: \(trusted ? "granted" : "not granted")")

        if !trusted {
            print("Global hotkeys require accessibility permissions.")
            print("Go to: System Settings → Privacy & Security → Accessibility → Enable Noot")
        }

        // Install event handler
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let handler: EventHandlerUPP = { _, event, userData -> OSStatus in
            print("🔥 Hotkey event received!")
            guard let userData = userData else {
                print("  ✗ No user data")
                return OSStatus(eventNotHandledErr)
            }
            let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()

            var hotkeyId = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &hotkeyId)

            print("  Hotkey ID: \(hotkeyId.id)")
            if let action = manager.hotkeys[hotkeyId.id] {
                print("  ✓ Executing action")
                DispatchQueue.main.async {
                    action()
                }
            } else {
                print("  ✗ No action found for ID")
            }

            return noErr
        }

        let userData = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, userData, &eventHandler)

        // Register default hotkeys
        registerDefaultHotkeys()
    }

    private func registerDefaultHotkeys() {
        // Option+Space - New Note
        registerHotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(optionKey), name: "Option+Space (New Note)") {
            NotificationCenter.default.post(name: .showCaptureWindow, object: nil)
        }

        // Cmd+Option+Space - Continue Note
        registerHotkey(keyCode: UInt32(kVK_Space), modifiers: UInt32(cmdKey | optionKey), name: "Cmd+Option+Space (Continue Note)") {
            NotificationCenter.default.post(name: .showContinueNote, object: nil)
        }

        // Cmd+Option+2 - Screenshot
        registerHotkey(keyCode: UInt32(kVK_ANSI_2), modifiers: UInt32(cmdKey | optionKey), name: "Cmd+Option+2 (Screenshot)") {
            NotificationCenter.default.post(name: .captureScreenshot, object: nil)
        }

        // Cmd+Option+3 - Screen Recording
        registerHotkey(keyCode: UInt32(kVK_ANSI_3), modifiers: UInt32(cmdKey | optionKey), name: "Cmd+Option+3 (Screen Recording)") {
            NotificationCenter.default.post(name: .toggleScreenRecording, object: nil)
        }

        // Cmd+Option+M - Meeting
        registerHotkey(keyCode: UInt32(kVK_ANSI_M), modifiers: UInt32(cmdKey | optionKey), name: "Cmd+Option+M (Meeting)") {
            NotificationCenter.default.post(name: .toggleMeeting, object: nil)
        }

        // Cmd+Option+I - Inbox
        registerHotkey(keyCode: UInt32(kVK_ANSI_I), modifiers: UInt32(cmdKey | optionKey), name: "Cmd+Option+I (Inbox)") {
            NotificationCenter.default.post(name: .showInbox, object: nil)
        }

        // Cmd+Option+O - Open Noot (main viewer)
        registerHotkey(keyCode: UInt32(kVK_ANSI_O), modifiers: UInt32(cmdKey | optionKey), name: "Cmd+Option+O (Open Noot)") {
            NotificationCenter.default.post(name: .showMainWindow, object: nil)
        }

        // Shift+Escape - Close/Save capture window (global dismiss, works without focus)
        registerHotkey(keyCode: UInt32(kVK_Escape), modifiers: UInt32(shiftKey), name: "Shift+Escape (Close Note)") {
            NotificationCenter.default.post(name: .dismissCaptureWindow, object: nil)
        }
    }

    private func registerHotkey(keyCode: UInt32, modifiers: UInt32, name: String, action: @escaping () -> Void) {
        let hotkeyId = nextHotkeyId
        nextHotkeyId += 1

        var hotkeyRef: EventHotKeyRef?
        let gHotkeyId = EventHotKeyID(signature: OSType(0x4E4F4F54), id: hotkeyId) // "NOOT"

        let carbonModifiers = carbonModifiersFromCocoa(modifiers)

        let status = RegisterEventHotKey(keyCode, carbonModifiers, gHotkeyId, GetApplicationEventTarget(), 0, &hotkeyRef)

        if status == noErr {
            hotkeys[hotkeyId] = action
            print("  ✓ Registered hotkey: \(name)")
        } else {
            print("  ✗ Failed to register hotkey \(name): error \(status)")
        }
    }

    private func carbonModifiersFromCocoa(_ modifiers: UInt32) -> UInt32 {
        var carbonMods: UInt32 = 0
        if modifiers & UInt32(cmdKey) != 0 { carbonMods |= UInt32(cmdKey) }
        if modifiers & UInt32(shiftKey) != 0 { carbonMods |= UInt32(shiftKey) }
        if modifiers & UInt32(optionKey) != 0 { carbonMods |= UInt32(optionKey) }
        if modifiers & UInt32(controlKey) != 0 { carbonMods |= UInt32(controlKey) }
        return carbonMods
    }

    deinit {
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }
}

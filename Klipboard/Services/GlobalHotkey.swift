import AppKit
import ApplicationServices
import Carbon.HIToolbox

enum HotkeyShortcut: String, CaseIterable {
    case optionV = "option_v"
    case cmdShiftV = "cmd_shift_v"

    var label: String {
        switch self {
        case .optionV: return "⌥V (Option + V)"
        case .cmdShiftV: return "⌘⇧V (Command + Shift + V)"
        }
    }

    var carbonModifiers: UInt32 {
        switch self {
        case .optionV: return UInt32(optionKey)
        case .cmdShiftV: return UInt32(cmdKey | shiftKey)
        }
    }
}

/// Listens system-wide for ⌥V (Option + V) and ⌘⇧V (Command + Shift + V)
/// using Carbon RegisterEventHotKey on GetApplicationEventTarget() plus
/// NSEvent/CGEventTap fallback so shortcuts toggle the panel open and closed.
final class GlobalHotkey {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTriggerTime: TimeInterval = 0

    var onTrigger: (() -> Void)?

    var activeShortcut: HotkeyShortcut {
        get {
            if let raw = UserDefaults.standard.string(forKey: "KlipboardShortcut"),
               let shortcut = HotkeyShortcut(rawValue: raw) {
                return shortcut
            }
            UserDefaults.standard.set(HotkeyShortcut.optionV.rawValue, forKey: "KlipboardShortcut")
            return .optionV
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: "KlipboardShortcut")
            start()
        }
    }

    func start() {
        stop()

        // Ensure any removed legacy preference (like cmd_v) is migrated to option_v
        _ = activeShortcut

        let carbonOptionVWorked = setupCarbonHotkeys()
        setupNSEventMonitors()
        setupEventTap(promptIfNeeded: !carbonOptionVWorked)
    }

    private func fireTrigger() {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - lastTriggerTime > 0.15 else { return }
        lastTriggerTime = now
        onTrigger?()
    }

    @discardableResult
    private func setupCarbonHotkeys() -> Bool {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let target = GetApplicationEventTarget()
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            target,
            { _, _, userData -> OSStatus in
                guard let userData else { return OSStatus(eventNotHandledErr) }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    hotkey.fireTrigger()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        var optionVRegistered = false
        let shortcutsToRegister: [HotkeyShortcut] = [.optionV, .cmdShiftV]
        for (index, shortcut) in shortcutsToRegister.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4B4C4950), id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                UInt32(kVK_ANSI_V),
                shortcut.carbonModifiers,
                hotKeyID,
                target,
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
                if shortcut == .optionV {
                    optionVRegistered = true
                }
            }
        }
        return optionVRegistered
    }

    private func setupNSEventMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if Self.matchesShortcut(keyCode: event.keyCode, flags: event.modifierFlags) {
                DispatchQueue.main.async {
                    self.fireTrigger()
                }
                return nil
            }
            return event
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return }
            if Self.matchesShortcut(keyCode: event.keyCode, flags: event.modifierFlags) {
                DispatchQueue.main.async {
                    self.fireTrigger()
                }
            }
        }
    }

    private func setupEventTap(promptIfNeeded: Bool) {
        guard eventTap == nil else { return }

        if promptIfNeeded && !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }

        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo -> Unmanaged<CGEvent>? in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userInfo).takeUnretainedValue()

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = hotkey.eventTap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                    }
                    return Unmanaged.passUnretained(event)
                }

                guard type == .keyDown else {
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
                let cgFlags = event.flags
                if GlobalHotkey.matchesCGShortcut(keyCode: keyCode, flags: cgFlags) {
                    DispatchQueue.main.async {
                        hotkey.fireTrigger()
                    }
                    return nil
                }

                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        ) else {
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.eventTap = tap
        self.runLoopSource = source
    }

    private static func matchesShortcut(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Bool {
        guard keyCode == UInt16(kVK_ANSI_V) else { return false }
        let mods = flags.intersection([.command, .option, .control, .shift])
        return mods == [.option] || mods == [.command, .shift]
    }

    private static func matchesCGShortcut(keyCode: UInt16, flags: CGEventFlags) -> Bool {
        guard keyCode == UInt16(kVK_ANSI_V) else { return false }
        let relevant: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let mods = flags.intersection(relevant)
        return mods == .maskAlternate || mods == [.maskCommand, .maskShift]
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil

        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }

        for ref in hotKeyRefs {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefs.removeAll()
        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        stop()
    }
}

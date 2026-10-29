import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Listens system-wide for the user's recorded shortcuts using Carbon
/// RegisterEventHotKey plus NSEvent/CGEventTap fallbacks, and reports which action fired.
final class GlobalHotkey {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var lastTriggerTime: [HotkeyAction: TimeInterval] = [:]
    private var combos: [(action: HotkeyAction, combo: KeyCombo)] = []

    var onTrigger: ((HotkeyAction) -> Void)?

    func start() {
        stop()
        combos = HotkeyAction.allCases.compactMap { action in
            Prefs.shortcut(for: action).map { (action, $0) }
        }
        guard !combos.isEmpty else { return }
        let allRegistered = setupCarbonHotkeys()
        setupNSEventMonitors()
        setupEventTap(promptIfNeeded: !allRegistered)
    }

    /// Carbon, the NSEvent monitor and the event tap can all see one keypress; fire once.
    private func fireTrigger(_ action: HotkeyAction) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now - (lastTriggerTime[action] ?? 0) > 0.15 else { return }
        lastTriggerTime[action] = now
        onTrigger?(action)
    }

    private func action(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> HotkeyAction? {
        combos.first { $0.combo.matches(keyCode: keyCode, flags: flags) }?.action
    }

    private func action(keyCode: UInt16, cgFlags: CGEventFlags) -> HotkeyAction? {
        combos.first { $0.combo.matches(keyCode: keyCode, cgFlags: cgFlags) }?.action
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
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var hotKeyID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &hotKeyID
                )
                guard status == noErr else { return status }
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
                let index = Int(hotKeyID.id) - 1
                DispatchQueue.main.async {
                    guard hotkey.combos.indices.contains(index) else { return }
                    hotkey.fireTrigger(hotkey.combos[index].action)
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        var allRegistered = true
        for (index, entry) in combos.enumerated() {
            var ref: EventHotKeyRef?
            let hotKeyID = EventHotKeyID(signature: OSType(0x4B4C4950), id: UInt32(index + 1))
            let status = RegisterEventHotKey(
                UInt32(entry.combo.keyCode),
                entry.combo.carbonModifiers,
                hotKeyID,
                target,
                0,
                &ref
            )
            if status == noErr, let ref {
                hotKeyRefs.append(ref)
            } else {
                allRegistered = false
            }
        }
        return allRegistered
    }

    private func setupNSEventMonitors() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(keyCode: event.keyCode, flags: event.modifierFlags) else {
                return event
            }
            DispatchQueue.main.async { self.fireTrigger(action) }
            return nil
        }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let action = self.action(keyCode: event.keyCode, flags: event.modifierFlags) else {
                return
            }
            DispatchQueue.main.async { self.fireTrigger(action) }
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
                if let action = hotkey.action(keyCode: keyCode, cgFlags: event.flags) {
                    DispatchQueue.main.async { hotkey.fireTrigger(action) }
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

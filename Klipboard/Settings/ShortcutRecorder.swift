import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Click, then press a key combination to assign it to `action`.
struct ShortcutRecorder: View {
    let action: HotkeyAction
    let onRecordingChange: (Bool) -> Void

    @AppStorage private var data: Data
    @State private var isRecording = false
    @State private var monitor: Any?

    init(action: HotkeyAction, onRecordingChange: @escaping (Bool) -> Void) {
        self.action = action
        self.onRecordingChange = onRecordingChange
        _data = AppStorage(wrappedValue: Data(), Prefs.Key.shortcut(action))
    }

    var body: some View {
        HStack(spacing: 6) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "Press keys…" : (KeyCombo.decode(data)?.display ?? "Record Shortcut"))
                    .frame(minWidth: 120)
            }
            Button {
                Prefs.setShortcut(nil, for: action)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Remove shortcut")
            .opacity(KeyCombo.decode(data) == nil ? 0 : 1)
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        isRecording = true
        onRecordingChange(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == UInt16(kVK_Escape) {
                stopRecording()
                return nil
            }
            // Require ⌘, ⌥ or ⌃ so a plain letter can't hijack typing everywhere.
            let flags = event.modifierFlags.intersection(KeyCombo.relevantFlags)
            guard !flags.subtracting(.shift).isEmpty else {
                NSSound.beep()
                return nil
            }
            Prefs.setShortcut(KeyCombo(event: event), for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard isRecording else { return }
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        onRecordingChange(false)
    }
}

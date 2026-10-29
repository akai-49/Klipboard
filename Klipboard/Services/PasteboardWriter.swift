import AppKit

enum PasteboardWriter {
    /// Writes the item back to the pasteboard, preserving its native type unless `plainText`
    /// asks for text only (no fonts or colours). Images and files have no plain form.
    static func write(_ item: ClipItem, plainText: Bool = false, to pasteboard: NSPasteboard = .general) {
        if plainText, item.type.hasPlainText, let text = item.text {
            writeString(text, to: pasteboard)
            return
        }
        pasteboard.clearContents()
        switch item.type {
        case .text, .url:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .rtf:
            if let data = item.payload {
                pasteboard.setData(data, forType: .rtf)
            }
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = item.payload {
                if let bitmap = NSBitmapImageRep(data: data) {
                    if let pngData = bitmap.representation(using: .png, properties: [:]) {
                        pasteboard.setData(pngData, forType: .png)
                    }
                    if let tiffData = bitmap.tiffRepresentation {
                        pasteboard.setData(tiffData, forType: .tiff)
                    }
                } else {
                    pasteboard.setData(data, forType: .png)
                }
            }
        case .file:
            let urls = item.pasteableFileURLs()
            if !urls.isEmpty {
                pasteboard.writeObjects(urls.map { $0 as NSURL })
            }
        case .color:
            if let data = item.payload {
                pasteboard.setData(data, forType: .init("com.apple.pasteboard.color"))
            }
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    static func writeString(_ string: String, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    /// Synthetic key events are silently dropped without Accessibility permission.
    @discardableResult
    static func ensureAccessibility(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        return false
    }

    /// Waits (up to ~500ms) for `app` to become active, then sends ⌘V to it.
    static func paste(into app: NSRunningApplication?, attempts: Int = 25) {
        if app == nil || app?.isActive == true || attempts == 0 {
            // Small grace period so the app's key window is ready for input.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { simulatePaste() }
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
            paste(into: app, attempts: attempts - 1)
        }
    }

    /// Simulates ⌘V so the copied item lands in whatever app was frontmost.
    static func simulatePaste() {
        // combinedSessionState + explicit flags so a still-held ⌥ (from ⌥V) doesn't leak in.
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v'
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}

import AppKit

enum PasteboardWriter {
    /// Writes the item back to the pasteboard, preserving its native type.
    static func write(_ item: ClipItem, to pasteboard: NSPasteboard = .general) {
        pasteboard.clearContents()
        switch item.type {
        case .text, .url:
            pasteboard.setString(item.text ?? "", forType: .string)
        case .rtf:
            if let data = item.data {
                pasteboard.setData(data, forType: .rtf)
            }
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        case .image:
            if let data = item.data {
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
            if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
            }
        case .color:
            if let data = item.data {
                pasteboard.setData(data, forType: .init("com.apple.pasteboard.color"))
            }
            if let text = item.text {
                pasteboard.setString(text, forType: .string)
            }
        }
    }

    /// Simulates ⌘V so the copied item lands in whatever app was frontmost.
    static func simulatePaste() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 'v'
        keyDown?.flags = .maskCommand
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

import AppKit
import Quartz
import SwiftUI

/// Full view of the selected entry, shown beside the list.
struct PreviewPane: View {
    let entry: PanelEntry?

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch entry {
            case .clip(let item):
                content(for: item)
                Divider()
                details(for: item)
            case .snippet(let snippet):
                Text(snippet.name).font(.headline)
                textView(snippet.text)
                Divider()
                Text("Snippet · \(snippet.text.count) characters")
                    .font(.caption).foregroundStyle(.secondary)
            case nil:
                Text("Nothing selected")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .leading) { Divider() }
    }

    @ViewBuilder
    private func content(for item: ClipItem) -> some View {
        switch item.type {
        case .text, .rtf:
            textView(item.text ?? "")
        case .url:
            textView(item.text ?? "", monospaced: true)
            if let text = item.text, let url = URL(string: text) {
                Button("Open Link") { NSWorkspace.shared.open(url) }
            }
        case .image:
            if let data = item.payload, let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if let rep = image.representations.first {
                    Text("\(rep.pixelsWide) × \(rep.pixelsHigh) px")
                        .font(.caption).foregroundStyle(.secondary)
                }
            } else {
                missing("Image is no longer available")
            }
        case .file:
            let urls = item.pasteableFileURLs()
            if let url = urls.first {
                QuickLookView(url: url)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if urls.count > 1 {
                    Text(urls.map(\.lastPathComponent).joined(separator: "\n"))
                        .font(.caption)
                        .lineLimit(6)
                }
                Text(url.path.hasPrefix(ClipItem.filesFolder.path) ? "Original was moved or deleted. Klipboard's saved copy will be pasted." : url.path)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            } else {
                missing(item.fileURLs.count > 1 ? "These files no longer exist" : "File no longer exists")
            }
        case .color:
            let hex = item.text ?? ""
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(hex: hex) ?? .gray)
                .frame(maxWidth: .infinity, maxHeight: 160)
            Text(hex).font(.system(.title3, design: .monospaced)).textSelection(.enabled)
            if let rgb = Self.rgb(hex) {
                Text(rgb).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled)
            }
        }
    }

    private func textView(_ text: String, monospaced: Bool = false) -> some View {
        ScrollView {
            Text(text)
                .font(.system(size: 12, design: monospaced ? .monospaced : .default))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxHeight: .infinity)
    }

    private func details(for item: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            if let app = item.sourceApp { Text("From \(app)") }
            Text(Self.dateFormatter.string(from: item.createdAt))
            if item.type.hasPlainText, let text = item.text {
                let lines = text.split(whereSeparator: \.isNewline).count
                Text("\(text.count) characters · \(lines) line\(lines == 1 ? "" : "s")")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func missing(_ message: String) -> some View {
        Text(message)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private static func rgb(_ hex: String) -> String? {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let value = UInt32(s, radix: 16) else { return nil }
        return "rgb(\(value >> 16 & 0xFF), \(value >> 8 & 0xFF), \(value & 0xFF))"
    }
}

private struct QuickLookView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> QLPreviewView {
        let view = QLPreviewView(frame: .zero, style: .compact) ?? QLPreviewView()
        view.autostarts = true
        return view
    }

    func updateNSView(_ view: QLPreviewView, context: Context) {
        if (view.previewItem as? URL) != url {
            view.previewItem = url as NSURL
        }
    }
}

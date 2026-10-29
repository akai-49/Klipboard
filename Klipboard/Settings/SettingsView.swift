import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @ObservedObject var snippets: SnippetStore
    /// Global hotkeys must be released while a shortcut is being recorded.
    let onRecordingChange: (Bool) -> Void

    var body: some View {
        TabView {
            GeneralSettings()
                .tabItem { Label("General", systemImage: "gearshape") }
            ShortcutSettings(onRecordingChange: onRecordingChange)
                .tabItem { Label("Shortcuts", systemImage: "keyboard") }
            PrivacySettings()
                .tabItem { Label("Privacy", systemImage: "hand.raised") }
            SnippetSettings(store: snippets)
                .tabItem { Label("Snippets", systemImage: "text.quote") }
        }
        .frame(width: 560, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @AppStorage(Prefs.Key.historyLimit) private var historyLimit = Prefs.Default.historyLimit
    @AppStorage(Prefs.Key.retentionDays) private var retentionDays = Prefs.Default.retentionDays
    @AppStorage(Prefs.Key.alwaysPlainText) private var alwaysPlainText = false
    @AppStorage(Prefs.Key.plainTextModifier) private var plainTextModifier = ModifierChoice.shift.rawValue
    @AppStorage(Prefs.Key.quickPasteModifier) private var quickPasteModifier = ModifierChoice.command.rawValue
    @AppStorage(Prefs.Key.previewOnHover) private var previewOnHover = false
    @AppStorage(Prefs.Key.hoverDelay) private var hoverDelay = Prefs.Default.hoverDelay
    @AppStorage(Prefs.Key.saveScreenshots) private var saveScreenshots = true
    @AppStorage(Prefs.Key.keepFileCopies) private var keepFileCopies = true
    @AppStorage(Prefs.Key.maxFileCopyMB) private var maxFileCopyMB = Prefs.Default.maxFileCopyMB

    private static let retentionPresets = [0, 1, 7, 30]
    private static let customRetention = -1

    @State private var retentionChoice = 0

    var body: some View {
        Form {
            Section("History") {
                Toggle("Unlimited history", isOn: Binding(
                    get: { historyLimit == 0 },
                    set: { historyLimit = $0 ? 0 : Prefs.Default.historyLimit }
                ))
                if historyLimit != 0 {
                    LabeledContent("Keep up to") {
                        HStack {
                            TextField("", value: $historyLimit, format: .number)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                            Stepper("", value: $historyLimit, in: 1...100_000, step: 10).labelsHidden()
                            Text("items")
                        }
                    }
                }
                Picker("Delete items older than", selection: $retentionChoice) {
                    Text("Never").tag(0)
                    Text("1 day").tag(1)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("Custom…").tag(Self.customRetention)
                }
                .onChange(of: retentionChoice) {
                    if retentionChoice != Self.customRetention { retentionDays = retentionChoice }
                }
                if retentionChoice == Self.customRetention {
                    LabeledContent("Days") {
                        TextField("", value: $retentionDays, format: .number)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Text("Pinned and favorite items are always kept.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Save screenshots to history", isOn: $saveScreenshots)
                Text("Screenshots saved as files (⌘⇧3, ⌘⇧4, ⌘⇧5) are added to Klipboard. Screenshots copied to the clipboard are always saved.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Copied files") {
                Toggle("Keep a copy of copied files", isOn: $keepFileCopies)
                if keepFileCopies {
                    LabeledContent("Only when the files total up to") {
                        HStack {
                            TextField("", value: $maxFileCopyMB, format: .number)
                                .frame(width: 80)
                                .multilineTextAlignment(.trailing)
                            Text("MB")
                        }
                    }
                }
                Text("Copied files still paste after the original is moved or deleted. On most Macs the copy takes no extra space until the original changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Pasting") {
                Toggle("Always paste as plain text", isOn: $alwaysPlainText)
                modifierPicker("Paste as plain text with", selection: $plainTextModifier, suffix: "↩ or click")
                modifierPicker("Quick paste items 1–9 with", selection: $quickPasteModifier, suffix: "1 … 9")
            }

            Section("Preview") {
                Toggle("Show preview when hovering an item", isOn: $previewOnHover)
                if previewOnHover {
                    LabeledContent("Delay") {
                        HStack {
                            Slider(value: $hoverDelay, in: 0...2, step: 0.1)
                            Text(String(format: "%.1f s", hoverDelay)).monospacedDigit().frame(width: 44)
                        }
                    }
                }
                Text("Press Space (when search is empty) or ⌘Y to preview the selected item.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            retentionChoice = Self.retentionPresets.contains(retentionDays) ? retentionDays : Self.customRetention
        }
    }

    private func modifierPicker(_ title: String, selection: Binding<String>, suffix: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(ModifierChoice.allCases) { choice in
                Text("\(choice.title)  \(choice.symbol)\(suffix)").tag(choice.rawValue)
            }
        }
    }
}

// MARK: - Shortcuts

private struct ShortcutSettings: View {
    let onRecordingChange: (Bool) -> Void

    var body: some View {
        Form {
            Section {
                ForEach(HotkeyAction.allCases) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(action: action, onRecordingChange: onRecordingChange)
                    }
                }
            } footer: {
                Text("Click a shortcut, then press the keys you want. Press Esc to cancel.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @AppStorage(Prefs.Key.skipConcealed) private var skipConcealed = true
    @AppStorage(Prefs.Key.maxTextLength) private var maxTextLength = Prefs.Default.maxTextLength
    @AppStorage(Prefs.Key.maxImageDimension) private var maxImageDimension = Prefs.Default.maxImageDimension
    @AppStorage(Prefs.Key.maxItemMB) private var maxItemMB = Prefs.Default.maxItemMB
    @AppStorage(Prefs.Key.pollInterval) private var pollInterval = Prefs.Default.pollInterval

    @State private var ignoredApps: [String] = Prefs.ignoredApps
    @State private var selection: String?

    var body: some View {
        Form {
            Section {
                Toggle("Don't save passwords from password managers", isOn: $skipConcealed)
            }

            Section {
                List(selection: $selection) {
                    ForEach(ignoredApps, id: \.self) { bundleID in
                        AppRow(bundleID: bundleID).tag(bundleID)
                    }
                }
                .frame(minHeight: 90)
                HStack {
                    Button { addApp() } label: { Image(systemName: "plus") }
                    Button { removeSelected() } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
            } header: {
                Text("Ignore copies from these apps")
            }

            Section("Limits") {
                numberRow("Longest text kept", value: $maxTextLength, unit: "characters")
                numberRow("Largest image size", value: $maxImageDimension, unit: "px")
                numberRow("Largest item", value: $maxItemMB, unit: "MB")
                LabeledContent("Check clipboard every") {
                    HStack {
                        TextField("", value: $pollInterval, format: .number.precision(.fractionLength(0...2)))
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                        Text("seconds")
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func numberRow(_ title: String, value: Binding<Int>, unit: String) -> some View {
        LabeledContent(title) {
            HStack {
                TextField("", value: value, format: .number)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                Text(unit)
            }
        }
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Ignore"
        guard panel.runModal() == .OK else { return }
        let ids = panel.urls.compactMap { Bundle(url: $0)?.bundleIdentifier }
        for id in ids where !ignoredApps.contains(id) {
            ignoredApps.append(id)
        }
        Prefs.ignoredApps = ignoredApps
    }

    private func removeSelected() {
        ignoredApps.removeAll { $0 == selection }
        selection = nil
        Prefs.ignoredApps = ignoredApps
    }
}

private struct AppRow: View {
    let bundleID: String

    var body: some View {
        let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        HStack {
            if let url {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                    .resizable()
                    .frame(width: 18, height: 18)
            }
            Text(url.map { FileManager.default.displayName(atPath: $0.path) } ?? bundleID)
        }
    }
}

// MARK: - Snippets

private struct SnippetSettings: View {
    @ObservedObject var store: SnippetStore
    @State private var selection: Snippet.ID?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(store.snippets) { snippet in
                        Text(snippet.name.isEmpty ? "Untitled" : snippet.name).tag(snippet.id)
                    }
                }
                HStack {
                    Button {
                        let snippet = store.add(name: "New Snippet", text: "")
                        selection = snippet.id
                    } label: { Image(systemName: "plus") }
                    Button {
                        if let selection { store.delete(id: selection) }
                        selection = nil
                    } label: { Image(systemName: "minus") }
                        .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .padding(6)
            }
            .frame(minWidth: 160, maxWidth: 200)

            Group {
                if let index = store.snippets.firstIndex(where: { $0.id == selection }) {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Name", text: $store.snippets[index].name)
                            .textFieldStyle(.roundedBorder)
                        TextEditor(text: $store.snippets[index].text)
                            .font(.system(size: 13))
                            .scrollContentBackground(.hidden)
                            .padding(4)
                            .background(Color(nsColor: .textBackgroundColor))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .padding(12)
                } else {
                    Text(store.snippets.isEmpty
                         ? "Add text you paste often, like your address or a reply template. Find snippets in the Snippets tab of Klipboard or by searching their name."
                         : "Select a snippet to edit it.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

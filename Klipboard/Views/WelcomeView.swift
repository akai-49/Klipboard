import AppKit
import SwiftUI

struct WelcomeView: View {
    let reason: WelcomePromptReason
    let onDone: () -> Void
    var onLaunchAtLoginChanged: (() -> Void)? = nil

    @State private var isAccessibilityGranted: Bool = AXIsProcessTrusted()
    @State private var openAtLogin: Bool = LaunchAtLogin.isEnabled
    @State private var openShortcut: KeyCombo? = Prefs.shortcut(for: .openPanel)
    @State private var autoCloseTask: Task<Void, Never>? = nil
    @State private var hasCompleted: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(reason == .firstLaunch ? "Welcome to Klipboard" : "Accessibility Permission")
                        .font(.title2.weight(.bold))
                    if reason == .firstLaunch {
                        if let combo = openShortcut {
                            Text("Press \(combo.display) to open your clipboard history anytime.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Click the menu bar icon to open your clipboard history anytime.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Grant accessibility access to paste directly into your active apps.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .center) {
                    Label("Accessibility Permission", systemImage: "hand.raised.fill")
                        .font(.headline)
                    Spacer()
                    if isAccessibilityGranted {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Allowed")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.green)
                        }
                    } else {
                        Button("Allow…") {
                            requestAccessibility()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text("Klipboard needs accessibility access to paste directly into the app you're using.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(12)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8))

            if reason == .firstLaunch {
                Toggle("Open Klipboard at login", isOn: $openAtLogin)
                    .onChange(of: openAtLogin) { newValue in
                        LaunchAtLogin.setEnabled(newValue)
                        onLaunchAtLoginChanged?()
                    }
            }

            Spacer()

            HStack {
                Spacer()
                Button("Done") {
                    complete()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440, height: 280)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let granted = AXIsProcessTrusted()
                if granted != isAccessibilityGranted {
                    isAccessibilityGranted = granted
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            let granted = AXIsProcessTrusted()
            if granted != isAccessibilityGranted {
                isAccessibilityGranted = granted
            }
            openShortcut = Prefs.shortcut(for: .openPanel)
        }
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            openShortcut = Prefs.shortcut(for: .openPanel)
        }
        .onChange(of: isAccessibilityGranted) { granted in
            if granted && WelcomeLogic.shouldAutoCloseOnAccessibilityGranted(for: reason) {
                autoCloseTask?.cancel()
                autoCloseTask = Task {
                    try? await Task.sleep(nanoseconds: 700_000_000)
                    guard !Task.isCancelled else { return }
                    complete()
                }
            }
        }
        .onAppear {
            isAccessibilityGranted = AXIsProcessTrusted()
            openAtLogin = LaunchAtLogin.isEnabled
            openShortcut = Prefs.shortcut(for: .openPanel)
        }
        .onDisappear {
            autoCloseTask?.cancel()
            autoCloseTask = nil
        }
    }

    private func complete() {
        guard !hasCompleted else { return }
        hasCompleted = true
        autoCloseTask?.cancel()
        autoCloseTask = nil
        onDone()
    }

    private func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
}

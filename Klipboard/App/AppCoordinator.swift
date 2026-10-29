import AppKit
import Carbon.HIToolbox
import Combine
import ServiceManagement
import SwiftUI

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let store = ClipboardStore()
    let snippets = SnippetStore()
    let viewModel: ClipboardViewModel
    let hotkey = GlobalHotkey()
    private var panel: FloatingPanel?
    private var settingsWindow: NSWindow?
    private var previousApp: NSRunningApplication?
    private var statusItem: NSStatusItem?
    private var panelKeyMonitor: Any?
    private var cancellables = Set<AnyCancellable>()
    private var activeShortcuts: [KeyCombo?] = []

    /// ANSI 1…9 key codes, in order.
    private static let digitKeyCodes: [UInt16] = [
        kVK_ANSI_1, kVK_ANSI_2, kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5,
        kVK_ANSI_6, kVK_ANSI_7, kVK_ANSI_8, kVK_ANSI_9,
    ].map { UInt16($0) }

    override init() {
        viewModel = ClipboardViewModel(store: store, snippets: snippets)
        super.init()
        viewModel.onRestoreFocus = { [weak self] in
            self?.restorePreviousAppFocus()
        }
    }

    func start() {
        setupStatusItem()
        hotkey.onTrigger = { [weak self] action in self?.perform(action) }
        startHotkeys()
        PasteboardWriter.ensureAccessibility(prompt: true)

        // Any setting change (Settings window, pause toggle) re-applies here.
        NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.applySettings() }
            .store(in: &cancellables)

        viewModel.$pasteStack
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in self?.refreshStatusItem() }
            .store(in: &cancellables)

        viewModel.$isPreviewing
            .removeDuplicates()
            .sink { [weak self] previewing in
                self?.panel?.setContentWidth(PanelLayout.width(previewing: previewing))
            }
            .store(in: &cancellables)

        // First run: enable launch-at-login and show the panel once. Later launches
        // (e.g. at login) stay silent in the menu bar and respect the user's toggle.
        let defaults = UserDefaults.standard
        let isTestHost = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        if !isTestHost, !defaults.bool(forKey: "didFirstLaunch") {
            defaults.set(true, forKey: "didFirstLaunch")
            try? SMAppService.mainApp.register()
            rebuildMenu()
            showPanel()
        }
    }

    private func startHotkeys() {
        activeShortcuts = HotkeyAction.allCases.map(Prefs.shortcut(for:))
        hotkey.start()
    }

    private func applySettings() {
        if HotkeyAction.allCases.map(Prefs.shortcut(for:)) != activeShortcuts {
            startHotkeys()
        }
        viewModel.applySettings()
        refreshStatusItem()
    }

    private func perform(_ action: HotkeyAction) {
        switch action {
        case .openPanel: togglePanel()
        case .pasteNext: viewModel.pasteNextFromStack()
        case .togglePasteStack: viewModel.togglePasteStack()
        case .togglePause: Prefs.isPaused.toggle()
        }
    }

    // MARK: Menu bar

    private func setupStatusItem() {
        if statusItem == nil {
            statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        }
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let button = statusItem?.button else { return }
        let paused = Prefs.isPaused
        let image = NSImage(
            systemSymbolName: paused ? "pause.circle" : "clipboard",
            accessibilityDescription: paused ? "Klipboard (paused)" : "Klipboard"
        )
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeft
        let stack = viewModel.pasteStack
        button.title = stack.isActive ? " \(stack.queue.count)" : ""
        let open = Prefs.shortcut(for: .openPanel).map { " (\($0.display))" } ?? ""
        button.toolTip = paused ? "Klipboard — recording paused" : "Klipboard\(open)"
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        menu.addItem(item("Open Clipboard History", #selector(handleOpenPanel), action: .openPanel))
        menu.addItem(.separator())

        let stack = viewModel.pasteStack
        let stackTitle = stack.isActive
            ? "Stop Paste Stack (\(stack.queue.count) to paste)"
            : "Start Paste Stack"
        menu.addItem(item(stackTitle, #selector(handleTogglePasteStack), action: .togglePasteStack))
        if stack.isActive {
            let next = item("Paste Next", #selector(handlePasteNext), action: .pasteNext)
            next.isEnabled = !stack.queue.isEmpty
            menu.addItem(next)
        }

        menu.addItem(item(
            Prefs.isPaused ? "Resume Recording" : "Pause Recording",
            #selector(handleTogglePause),
            action: .togglePause
        ))
        menu.addItem(item("Clear History…", #selector(handleClearHistory)))
        menu.addItem(.separator())

        let settings = item("Settings…", #selector(handleOpenSettings))
        settings.keyEquivalent = ","
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        let loginItem = item("Launch at Login", #selector(handleToggleLaunchAtLogin))
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())
        let quitItem = item("Quit Klipboard", #selector(handleQuit))
        quitItem.keyEquivalent = "q"
        quitItem.keyEquivalentModifierMask = [.command]
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    /// Menu item that shows the action's recorded shortcut, if any.
    private func item(_ title: String, _ selector: Selector, action: HotkeyAction? = nil) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: selector, keyEquivalent: "")
        menuItem.target = self
        if let action, let combo = Prefs.shortcut(for: action), combo.key.count == 1 {
            menuItem.keyEquivalent = combo.key.lowercased()
            menuItem.keyEquivalentModifierMask = combo.flags
        }
        return menuItem
    }

    @objc private func handleOpenPanel() { showPanel() }
    @objc private func handleTogglePasteStack() { viewModel.togglePasteStack() }
    @objc private func handlePasteNext() { viewModel.pasteNextFromStack() }
    @objc private func handleTogglePause() { Prefs.isPaused.toggle() }

    @objc private func handleClearHistory() {
        let alert = NSAlert()
        alert.messageText = "Clear clipboard history?"
        alert.informativeText = "This can't be undone."
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Keep pinned and favorite items"
        alert.suppressionButton?.state = .on
        NSApp.activate(ignoringOtherApps: true)
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        viewModel.clearHistory(keepPinnedAndFavorites: alert.suppressionButton?.state == .on)
    }

    @objc private func handleOpenSettings() {
        panel?.dismiss()
        if settingsWindow == nil {
            let view = SettingsView(snippets: snippets) { [weak self] recording in
                guard let self else { return }
                if recording { self.hotkey.stop() } else { self.startHotkeys() }
            }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = "Klipboard Settings"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func handleToggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .enabled {
            try? service.unregister()
        } else {
            try? service.register()
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        }
        rebuildMenu()
    }

    @objc private func handleQuit() {
        NSApplication.shared.terminate(nil)
    }

    // MARK: Panel

    func togglePanel() {
        if let panel, panel.isVisible {
            panel.dismiss()
            restorePreviousAppFocus()
            return
        }
        showPanel()
    }

    func showPanel() {
        if let frontmost = NSWorkspace.shared.frontmostApplication,
           frontmost.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = frontmost
        }
        if panel == nil {
            panel = FloatingPanel(content: ClipboardPanelView(viewModel: viewModel, dismiss: { [weak self] in
                self?.panel?.dismiss()
            }))
            installPanelKeyMonitor()
        }
        viewModel.isPreviewing = false
        viewModel.selectedIndex = 0
        panel?.setContentWidth(PanelLayout.listWidth)
        panel?.showCentered()
    }

    /// Keys the search field would otherwise swallow: Return (± plain-text modifier),
    /// quick paste digits, ⌘←/⌘→ for filters, Space/⌘Y for preview.
    private func installPanelKeyMonitor() {
        panelKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel else { return event }
            return self.handlePanelKey(event, in: panel) ? nil : event
        }
    }

    private func handlePanelKey(_ event: NSEvent, in panel: FloatingPanel) -> Bool {
        // Leave keys alone while an input method is composing text.
        if let editor = panel.firstResponder as? NSTextView, editor.hasMarkedText() { return false }
        let flags = event.modifierFlags.intersection(KeyCombo.relevantFlags)
        let dismiss: () -> Void = { [weak self] in self?.panel?.dismiss() }

        switch Int(event.keyCode) {
        case kVK_Escape where viewModel.isPreviewing:
            viewModel.isPreviewing = false
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            guard let entry = viewModel.selectedEntry else { return true }
            viewModel.paste(entry, plainText: flags.contains(Prefs.plainTextModifier.flag), dismiss: dismiss)
            return true
        case kVK_LeftArrow where flags == .command, kVK_RightArrow where flags == .command:
            let all = ClipFilter.allCases
            let index = all.firstIndex(of: viewModel.filter) ?? 0
            let step = event.keyCode == UInt16(kVK_LeftArrow) ? -1 : 1
            viewModel.filter = all[(index + step + all.count) % all.count]
            return true
        case kVK_Space where flags.isEmpty && viewModel.searchText.isEmpty,
             kVK_ANSI_Y where flags == .command:
            viewModel.isPreviewing.toggle()
            return true
        default:
            break
        }

        if let digit = Self.digitKeyCodes.firstIndex(of: event.keyCode),
           flags == Prefs.quickPasteModifier.flag {
            if let entry = viewModel.entries[safe: digit] {
                viewModel.paste(entry, plainText: false, dismiss: dismiss)
            }
            return true
        }
        return false
    }

    @discardableResult
    private func restorePreviousAppFocus() -> NSRunningApplication? {
        // Hiding hands activation back immediately; activate() alone is async and can lag.
        NSApp.hide(nil)
        previousApp?.activate()
        return previousApp
    }
}

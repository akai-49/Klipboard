import AppKit
import ServiceManagement

@MainActor
final class AppCoordinator: NSObject, ObservableObject {
    let store = ClipboardStore()
    let viewModel: ClipboardViewModel
    let hotkey = GlobalHotkey()
    @Published var selectedShortcut: HotkeyShortcut
    private var panel: FloatingPanel?
    private var previousApp: NSRunningApplication?
    private var statusItem: NSStatusItem?

    override init() {
        selectedShortcut = hotkey.activeShortcut
        viewModel = ClipboardViewModel(store: store)
        super.init()
        viewModel.onRestoreFocus = { [weak self] in
            self?.restorePreviousAppFocus()
        }
    }

    func start() {
        setupStatusItem()
        hotkey.onTrigger = { [weak self] in self?.togglePanel() }
        hotkey.start()
        PasteboardWriter.ensureAccessibility(prompt: true)

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

    private func setupStatusItem() {
        guard statusItem == nil else {
            rebuildMenu()
            return
        }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "clipboard", accessibilityDescription: "Klipboard")
            image?.isTemplate = true
            button.image = image
            button.toolTip = "Klipboard (⌥V)"
        }
        statusItem = item
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let openItem = NSMenuItem(
            title: "Open Clipboard History",
            action: #selector(handleOpenPanel),
            keyEquivalent: "v"
        )
        openItem.keyEquivalentModifierMask = [.option]
        openItem.target = self
        menu.addItem(openItem)

        let shortcutMenu = NSMenu()
        for shortcut in HotkeyShortcut.allCases {
            let sItem = NSMenuItem(
                title: shortcut.label,
                action: #selector(handleSelectShortcut(_:)),
                keyEquivalent: ""
            )
            sItem.target = self
            sItem.representedObject = shortcut.rawValue
            sItem.state = (selectedShortcut == shortcut) ? .on : .off
            shortcutMenu.addItem(sItem)
        }
        let shortcutRoot = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutRoot.submenu = shortcutMenu
        menu.addItem(shortcutRoot)

        let loginItem = NSMenuItem(
            title: "Launch at Login",
            action: #selector(handleToggleLaunchAtLogin),
            keyEquivalent: ""
        )
        loginItem.target = self
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(loginItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit Klipboard",
            action: #selector(handleQuit),
            keyEquivalent: "q"
        )
        quitItem.keyEquivalentModifierMask = [.command]
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    @objc private func handleOpenPanel() {
        showPanel()
    }

    @objc private func handleSelectShortcut(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let shortcut = HotkeyShortcut(rawValue: raw) else { return }
        setShortcut(shortcut)
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

    func setShortcut(_ shortcut: HotkeyShortcut) {
        selectedShortcut = shortcut
        hotkey.activeShortcut = shortcut
        rebuildMenu()
    }

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
        }
        viewModel.selectedIndex = 0
        panel?.showCentered()
    }

    @discardableResult
    private func restorePreviousAppFocus() -> NSRunningApplication? {
        // Hiding hands activation back immediately; activate() alone is async and can lag.
        NSApp.hide(nil)
        previousApp?.activate()
        return previousApp
    }
}

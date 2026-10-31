import AppKit
import SwiftUI

/// Spotlight-style borderless panel: floats above everything, doesn't steal
/// focus from other apps until shown, closes on Esc/resign, user-resizable.
final class FloatingPanel: NSPanel, NSWindowDelegate {
    private var isShowing = false
    private var isProgrammaticResize = false
    private var preExpandOriginX: CGFloat?
    var isPreviewingActive = false

    init(content: some View) {
        let initialWidth = max(PanelLayout.minWidth, Prefs.panelWidth)
        let initialHeight = max(PanelLayout.minHeight, Prefs.panelHeight)

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: initialWidth, height: initialHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable, .resizable],
            backing: .buffered,
            defer: true
        )
        delegate = self
        minSize = NSSize(width: PanelLayout.minWidth, height: PanelLayout.minHeight)
        isFloatingPanel = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = .clear
        hasShadow = true
        isReleasedWhenClosed = false

        let blur = NSVisualEffectView()
        blur.material = .popover
        blur.blendingMode = .behindWindow
        blur.state = .followsWindowActiveState
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 16
        blur.layer?.masksToBounds = true

        let hosting = NSHostingView(rootView: content)
        hosting.translatesAutoresizingMaskIntoConstraints = false
        blur.addSubview(hosting)
        NSLayoutConstraint.activate([
            hosting.leadingAnchor.constraint(equalTo: blur.leadingAnchor),
            hosting.trailingAnchor.constraint(equalTo: blur.trailingAnchor),
            hosting.topAnchor.constraint(equalTo: blur.topAnchor),
            hosting.bottomAnchor.constraint(equalTo: blur.bottomAnchor),
        ])
        contentView = blur
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func resignKey() {
        super.resignKey()
        guard !isShowing, attachedSheet == nil, NSApp.modalWindow == nil else { return }
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func showCentered() {
        isShowing = true
        let width = max(PanelLayout.minWidth, Prefs.panelWidth)
        let height = max(PanelLayout.minHeight, Prefs.panelHeight)
        let targetRect = frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: width, height: height)))

        let mouseLoc = NSEvent.mouseLocation
        let targetScreen = NSScreen.screens.first(where: {
            NSMouseInRect(mouseLoc, $0.frame, false)
        }) ?? NSScreen.main ?? screen

        if let targetScreen {
            let visible = targetScreen.visibleFrame
            let originX = visible.midX - (targetRect.width / 2)
            let originY = visible.midY - (targetRect.height / 2)
            setFrame(NSRect(x: originX, y: originY, width: targetRect.width, height: targetRect.height), display: false)
        } else {
            center()
        }
        keepOnScreen()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isShowing = false
        }
    }

    /// Grows or shrinks to the right, keeping the list under the mouse, and stays on screen.
    func setContentWidth(_ width: CGFloat, isPreviewing: Bool? = nil) {
        if let isPreviewing {
            if isPreviewing && !self.isPreviewingActive {
                preExpandOriginX = frame.origin.x
            }
            self.isPreviewingActive = isPreviewing
        }
        isProgrammaticResize = true
        defer { isProgrammaticResize = false }

        var newFrame = frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: width, height: contentLayoutRect.height)))
        guard newFrame.width != frame.width else {
            keepOnScreen()
            return
        }
        newFrame.origin = frame.origin

        if !self.isPreviewingActive, let preX = preExpandOriginX {
            newFrame.origin.x = preX
            preExpandOriginX = nil
        } else if let visible = screen?.visibleFrame, newFrame.maxX > visible.maxX {
            newFrame.origin.x = max(visible.minX, visible.maxX - newFrame.width)
        }
        setFrame(newFrame, display: true)
        keepOnScreen()
    }

    /// Keeps the panel within the visible bounds of the current screen.
    func keepOnScreen() {
        guard let screen = self.screen ?? NSScreen.main else { return }
        let visible = screen.visibleFrame
        var newFrame = frame

        if newFrame.width > visible.width {
            newFrame.size.width = visible.width
        }
        if newFrame.height > visible.height {
            newFrame.size.height = visible.height
        }

        if newFrame.maxX > visible.maxX {
            newFrame.origin.x = visible.maxX - newFrame.width
        }
        if newFrame.minX < visible.minX {
            newFrame.origin.x = visible.minX
        }
        if newFrame.maxY > visible.maxY {
            newFrame.origin.y = visible.maxY - newFrame.height
        }
        if newFrame.minY < visible.minY {
            newFrame.origin.y = visible.minY
        }

        if newFrame != frame {
            setFrame(newFrame, display: true)
        }
    }

    func windowDidResize(_ notification: Notification) {
        guard !isShowing, !isProgrammaticResize else { return }
        let contentSize = contentLayoutRect.size

        if isPreviewingActive {
            Prefs.panelWidth = PanelLayout.listWidth(for: contentSize.width)
        } else {
            Prefs.panelWidth = contentSize.width
        }
        Prefs.panelHeight = contentSize.height
    }

    func dismiss() {
        isShowing = false
        makeFirstResponder(nil)
        orderOut(nil)
    }
}

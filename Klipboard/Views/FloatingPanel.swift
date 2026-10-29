import AppKit
import SwiftUI

/// Spotlight-style borderless panel: floats above everything, doesn't steal
/// focus from other apps until shown, closes on Esc/resign.
final class FloatingPanel: NSPanel {
    private var isShowing = false

    init(content: some View) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: PanelLayout.listWidth, height: PanelLayout.height),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView, .closable],
            backing: .buffered,
            defer: true
        )
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
        guard !isShowing else { return }
        dismiss()
    }

    override func cancelOperation(_ sender: Any?) {
        dismiss()
    }

    func showCentered() {
        isShowing = true
        center()
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.isShowing = false
        }
    }

    /// Grows or shrinks to the right, keeping the list under the mouse, and stays on screen.
    func setContentWidth(_ width: CGFloat) {
        var newFrame = frameRect(forContentRect: NSRect(origin: .zero, size: NSSize(width: width, height: contentLayoutRect.height)))
        guard newFrame.width != frame.width else { return }
        newFrame.origin = frame.origin
        if let visible = screen?.visibleFrame, newFrame.maxX > visible.maxX {
            newFrame.origin.x = max(visible.minX, visible.maxX - newFrame.width)
        }
        setFrame(newFrame, display: true)
    }

    func dismiss() {
        isShowing = false
        makeFirstResponder(nil)
        orderOut(nil)
    }
}

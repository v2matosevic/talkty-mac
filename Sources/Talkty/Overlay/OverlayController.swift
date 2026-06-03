import AppKit
import SwiftUI

/// Owns the overlay panel: shows/hides it and positions it bottom-center of the
/// active screen's visible area (excludes the menu bar + Dock), repositioning each
/// time it appears in case the user switched monitors.
@MainActor
final class OverlayController {
    private var panel: OverlayPanel?
    private let panelSize = NSSize(width: 240, height: 64)
    private let bottomMargin: CGFloat = 40
    /// Bumped on every show(); a pending hide that captured an older value is stale
    /// (a new take started during its fade) and must not order the panel out.
    private var generation = 0

    func show(state: AppState) {
        generation &+= 1
        let panel = ensurePanel(state: state)
        reposition(panel)
        // Already up (e.g. rapid stop→start cancelled the hide): just reposition,
        // don't restart the fade — that would flicker.
        if panel.isVisible && panel.alphaValue > 0.99 { return }
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 1
        }
    }

    func hide() {
        guard let panel else { return }
        let gen = generation
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.18
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A show() since this fade began means a new take is live — keep it.
                guard let self, self.generation == gen else { return }
                panel.orderOut(nil)
            }
        })
    }

    private func ensurePanel(state: AppState) -> OverlayPanel {
        if let panel { return panel }
        let p = OverlayPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        let root = ZStack { OverlayView(state: state) }
            .frame(width: panelSize.width, height: panelSize.height)
        let hosting = NSHostingView(rootView: root)
        hosting.frame = NSRect(origin: .zero, size: panelSize)
        p.contentView = hosting
        panel = p
        return p
    }

    private func reposition(_ panel: OverlayPanel) {
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let x = visible.midX - panelSize.width / 2
        let y = visible.minY + bottomMargin
        panel.setFrame(NSRect(x: x, y: y, width: panelSize.width, height: panelSize.height), display: true)
    }

    /// Screen containing the mouse, falling back to the main screen.
    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
            ?? NSScreen.screens[0]
    }
}

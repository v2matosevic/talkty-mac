import AppKit
import SwiftUI
import TalktyKit

/// Reusable host for a SwiftUI window with the app's dark chrome. The Settings,
/// About, and Onboarding controllers below start as thin placeholders and are
/// fleshed out in Phases 4–5.
final class DarkWindowController: NSWindowController {
    init(title: String, size: NSSize, content: some View) {
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: size),
                              styleMask: [.titled, .closable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = title
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Theme.bg)
        // A programmatically-created NSWindow defaults to isReleasedWhenClosed=true:
        // closing it deallocates the window while our strong `let` still points at it,
        // so reopening retains freed memory → EXC_BAD_ACCESS. We own the lifetime via
        // the controller, so opt out.
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView:
            AnyView(content.frame(width: size.width, height: size.height).background(Theme.bg))
        )
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

private struct Placeholder: View {
    let title: String
    var body: some View {
        VStack(spacing: 8) {
            Text(title).font(.system(size: 18, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text("Coming together in the next build.").font(.system(size: 13)).foregroundStyle(Theme.textMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private let vm: SettingsViewModel
    private let models = ModelManager()

    init(settings: SettingsStore, state: AppState, onApply: @escaping () -> Void) {
        vm = SettingsViewModel(store: settings, onApply: onApply)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 440, height: 720),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Settings"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Theme.bg)
        // See DarkWindowController: opt out of release-on-close so reopening Settings
        // doesn't retain a freed NSWindow (EXC_BAD_ACCESS in show()).
        window.isReleasedWhenClosed = false
        window.center()

        let root = SettingsView(vm: vm, models: models,
                                onSave: { [weak window] in window?.close() },
                                onCancel: { [weak window] in window?.close() })
        window.contentView = NSHostingView(rootView: root)
        super.init()
        window.delegate = self
    }

    func show() {
        models.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // Stop the permission watch whenever the window closes (Save/Cancel/X all route here).
    func windowWillClose(_ notification: Notification) { vm.stopPermissionWatch() }
}

@MainActor
final class AboutWindowController {
    private let controller: DarkWindowController
    init(version: String) {
        controller = DarkWindowController(title: "About Talkty", size: NSSize(width: 400, height: 340),
                                          content: AboutView(version: version))
    }
    func show() { controller.show() }
}

@MainActor
final class OnboardingWindowController {
    private let controller: DarkWindowController
    init(hotkey: String, onOpenSettings: @escaping () -> Void, onFinish: @escaping () -> Void) {
        var ctrlRef: DarkWindowController?
        let c = DarkWindowController(
            title: "Welcome", size: NSSize(width: 500, height: 420),
            content: OnboardingView(hotkey: hotkey,
                                    onOpenSettings: { ctrlRef?.close(); onOpenSettings() },
                                    onGetStarted: { ctrlRef?.close(); onFinish() }))
        ctrlRef = c
        controller = c
    }
    func show() { controller.show() }
}

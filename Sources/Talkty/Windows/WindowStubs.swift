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
final class SettingsWindowController {
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
        window.center()

        let root = SettingsView(vm: vm, models: models,
                                onSave: { [weak window] in window?.close() },
                                onCancel: { [weak window] in window?.close() })
        window.contentView = NSHostingView(rootView: root)
    }

    func show() {
        models.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

final class AboutWindowController {
    private let controller: DarkWindowController
    init(version: String) {
        controller = DarkWindowController(title: "About Talkty", size: NSSize(width: 400, height: 340),
                                          content: Placeholder(title: "Talkty \(version)"))
    }
    func show() { controller.show() }
}

final class OnboardingWindowController {
    private let controller: DarkWindowController
    init(settings: SettingsStore, hotkey: HotkeyConfig, onFinish: @escaping () -> Void) {
        controller = DarkWindowController(title: "Welcome", size: NSSize(width: 500, height: 380),
                                          content: Placeholder(title: "Welcome to Talkty"))
        // Auto-mark onboarding complete for now so it doesn't block; real flow in Phase 5.
        onFinish()
    }
    func show() { controller.show() }
}

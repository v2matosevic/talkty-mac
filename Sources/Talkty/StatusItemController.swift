import AppKit
import Combine
import TalktyKit

/// Menu-bar presence (NSStatusItem) + menu. Replaces the Windows tray icon.
/// Reflects the recording state in the menu-bar glyph.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let state: AppState
    private var cancellable: AnyCancellable?

    var onOpen: (() -> Void)?
    var onToggle: (() -> Void)?
    var onOpenSettings: (() -> Void)?
    var onOpenAbout: (() -> Void)?
    var onQuit: (() -> Void)?

    private let toggleItem = NSMenuItem(title: "Start Recording", action: nil, keyEquivalent: "")
    private let statusItem = NSMenuItem(title: "Ready", action: nil, keyEquivalent: "")

    init(state: AppState) {
        self.state = state
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        configureButton()
        item.menu = buildMenu()
        cancellable = state.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.refresh() }
        }
    }

    private func configureButton() {
        if let button = item.button {
            button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Talkty")
            button.image?.isTemplate = true
            button.toolTip = "Talkty"
        }
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(.separator())

        let open = NSMenuItem(title: "Open Talkty", action: #selector(openMain), keyEquivalent: "o")
        open.target = self
        menu.addItem(open)

        toggleItem.target = self
        toggleItem.action = #selector(toggle)
        menu.addItem(toggleItem)
        menu.addItem(.separator())

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let about = NSMenuItem(title: "About Talkty", action: #selector(openAbout), keyEquivalent: "")
        about.target = self
        menu.addItem(about)
        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Talkty", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        return menu
    }

    private func refresh() {
        statusItem.title = state.statusText
        let recording = state.recordingState == .listening
        let transcribing = state.recordingState == .transcribing
        toggleItem.title = recording ? "Stop Recording" : "Start Recording"
        if let button = item.button {
            let symbol = recording ? "mic.fill" : (transcribing ? "waveform" : "mic.fill")
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Talkty")
            button.image?.isTemplate = true
            button.contentTintColor = recording ? NSColor.systemRed : nil
            // Live elapsed time next to the glyph while recording.
            button.title = recording ? " \(state.elapsedDisplay)" : ""
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        }
    }

    @objc private func openMain() { onOpen?() }
    @objc private func toggle() { onToggle?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openAbout() { onOpenAbout?() }
    @objc private func quit() { onQuit?() }
}

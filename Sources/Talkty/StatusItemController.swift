import AppKit
import Combine
import TalktyKit

/// Menu-bar presence (NSStatusItem) + menu. Replaces the Windows tray icon.
/// Reflects the recording state in the menu-bar glyph.
@MainActor
final class StatusItemController {
    private let item: NSStatusItem
    private let state: AppState
    private var cancellables: Set<AnyCancellable> = []

    // Built once — rebuilding NSImage(systemSymbolName:) on every state tick was
    // ~22 allocations/sec during recording (audioLevel + elapsed publishers).
    private static let micImage: NSImage? = {
        let img = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Talkty")
        img?.isTemplate = true
        return img
    }()
    private static let waveformImage: NSImage? = {
        let img = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Talkty")
        img?.isTemplate = true
        return img
    }()

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
        // Narrow subscriptions instead of objectWillChange: the glyph/menu only change
        // on recordingState transitions, the clock only needs the button title, and
        // audioLevel (~12 Hz while recording) never reaches the menu bar at all.
        // @Published emits on willSet, so sinks use the passed value, not state.*.
        state.$recordingState
            .removeDuplicates()
            .sink { [weak self] in self?.refresh(for: $0) }
            .store(in: &cancellables)
        state.$statusText
            .removeDuplicates()
            .sink { [weak self] in self?.statusItem.title = $0 }
            .store(in: &cancellables)
        state.$elapsed
            .map { Int($0) }            // the clock shows whole seconds…
            .removeDuplicates()         // …so skip the 10 Hz timer's identical ticks
            .sink { [weak self] total in
                guard let self, self.state.recordingState == .listening else { return }
                self.item.button?.title = String(format: " %02d:%02d", total / 60, total % 60)
            }
            .store(in: &cancellables)
    }

    private func configureButton() {
        if let button = item.button {
            button.image = Self.micImage
            button.toolTip = "Talkty"
            button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
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

    /// Glyph/tint/menu refresh — runs only on recordingState transitions (a handful
    /// per take), not on every published tick.
    private func refresh(for recordingState: RecordingState) {
        let recording = recordingState == .listening
        let transcribing = recordingState == .transcribing
        toggleItem.title = recording ? "Stop Recording" : "Start Recording"
        if let button = item.button {
            button.image = transcribing ? Self.waveformImage : Self.micImage
            button.contentTintColor = recording ? NSColor.systemRed : nil
            // The live clock is appended by the $elapsed subscription while recording.
            button.title = recording ? " 00:00" : ""
        }
    }

    @objc private func openMain() { onOpen?() }
    @objc private func toggle() { onToggle?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func openAbout() { onOpenAbout?() }
    @objc private func quit() { onQuit?() }
}

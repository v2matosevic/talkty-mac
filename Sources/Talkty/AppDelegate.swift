import AppKit
import TalktyKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let history = HistoryStore()
    private let state = AppState()
    private let overlay = OverlayController()
    private let update = UpdateService()

    private var dictation: DictationController!
    private var statusItem: StatusItemController!

    private var mainWindow: MainWindowController?
    private var settingsWindow: SettingsWindowController?
    private var aboutWindow: AboutWindowController?
    private var onboardingWindow: OnboardingWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSSetUncaughtExceptionHandler { exception in
            Log.error("Uncaught exception: \(exception.name.rawValue) — \(exception.reason ?? "")")
        }
        Log.info("Talkty launching (build \(update.currentVersion))")
        settings.update { $0.hints.appLaunchCount += 1 }

        dictation = DictationController(state: state, settings: settings, history: history, overlay: overlay)
        statusItem = StatusItemController(state: state)
        wireStatusItem()
        observeNotifications()

        if settings.settings.showNotification { Notifications.requestAuthorization() }

        dictation.registerHotkey()
        dictation.loadModel()

        // First run → onboarding; otherwise check for updates in the background.
        if !settings.settings.hints.hasCompletedOnboarding {
            showOnboarding()
        }
        Task { [weak self] in
            guard let self else { return }
            if let info = await self.update.checkForUpdates() {
                self.state.updateAvailable = info
                Log.info("Update available: \(info.latestVersion)")
            }
        }
    }

    private func wireStatusItem() {
        statusItem.onOpen = { [weak self] in self?.showMainWindow() }
        statusItem.onToggle = { [weak self] in self?.dictation.toggle() }
        statusItem.onOpenSettings = { [weak self] in self?.showSettings() }
        statusItem.onOpenAbout = { [weak self] in self?.showAbout() }
        statusItem.onQuit = { [weak self] in self?.quit() }
    }

    func showMainWindow() {
        if mainWindow == nil {
            mainWindow = MainWindowController(state: state, history: history,
                                              onToggle: { [weak self] in self?.dictation.toggle() },
                                              onSettings: { [weak self] in self?.showSettings() })
        }
        mainWindow?.show()
    }

    private func observeNotifications() {
        let nc = NotificationCenter.default
        nc.addObserver(forName: .talktyOpenSettings, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showSettings() }
        }
        nc.addObserver(forName: .talktyShowOnboarding, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.showOnboarding() }
        }
    }

    // MARK: Windows

    func showSettings() {
        if settingsWindow == nil {
            settingsWindow = SettingsWindowController(settings: settings, state: state, onApply: { [weak self] in
                self?.dictation.updateHotkey(self!.settings.settings.hotkey)
                self?.dictation.loadModel()
            })
        }
        settingsWindow?.show()
    }

    func showAbout() {
        if aboutWindow == nil { aboutWindow = AboutWindowController(version: update.currentVersion) }
        aboutWindow?.show()
    }

    func showOnboarding() {
        if onboardingWindow == nil {
            onboardingWindow = OnboardingWindowController(
                hotkey: settings.settings.hotkey.displayString,
                onOpenSettings: { [weak self] in
                    self?.settings.update { $0.hints.hasCompletedOnboarding = true }
                    self?.showSettings()
                },
                onFinish: { [weak self] in
                    self?.settings.update { $0.hints.hasCompletedOnboarding = true }
                })
        }
        onboardingWindow?.show()
    }

    // MARK: Lifecycle

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    private func quit() { NSApp.terminate(nil) }

    /// Runs on EVERY termination path (menu, ⌘Q, Apple Event, logout). Flush our
    /// own state, then _exit(0) to bypass ggml-metal's asserting C++ static
    /// destructors (see CLAUDE.md) — the OS reclaims everything.
    func applicationWillTerminate(_ notification: Notification) {
        Log.info("Talkty quitting")
        dictation.hotkey.unregisterToggle()
        dictation.transcription.unload()
        settings.save()
        Log.shared.flush()
        _exit(0)
    }
}

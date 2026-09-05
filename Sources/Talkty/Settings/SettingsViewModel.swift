import AppKit
import SwiftUI
import TalktyKit

/// Working state for the settings window: an editable draft of AppSettings plus
/// the live mic test and the hotkey recorder.
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var draft: AppSettings
    @Published var inputDevices: [AudioDevice] = []

    // Hotkey recorder
    @Published var recordingHotkey = false
    private var hotkeyMonitor: Any?

    // Mic test
    @Published var testing = false
    @Published var testLevel: Float = 0
    @Published var testStatus = ""
    private let testCapture = AudioCaptureService()

    // Mic input volume — the system-wide hardware level (System Settings → Sound →
    // Input). nil = the selected device doesn't expose a volume control.
    @Published var micVolume: Float?

    // Vocabulary editors: comma-joined terms, and one "misheard => correct" rule per line.
    @Published var vocabularyText: String
    @Published var replacementsText: String

    // OpenRouter API key. We do NOT read the stored secret (that would trigger a Keychain
    // access prompt every time Settings opens) — we only check existence. The field starts
    // empty; typing a value replaces the stored key on save, leaving it blank keeps the
    // existing one, and "Remove" clears it. Powers cloud transcription + Prompting.
    @Published var openRouterKey: String = ""
    @Published var hasStoredKey: Bool = KeychainService.hasOpenRouterKey
    private var removeKeyRequested = false

    // Auto-paste permission status (refreshed when the app regains focus, e.g. after
    // the user returns from System Settings).
    @Published var accessibilityGranted = PermissionsService.hasAccessibility
    private var activeObserver: NSObjectProtocol?

    private let store: SettingsStore
    private let onApply: () -> Void

    init(store: SettingsStore, onApply: @escaping () -> Void) {
        self.store = store
        self.onApply = onApply
        let s = store.settings
        self.draft = s
        self.vocabularyText = (s.customVocabulary ?? DefaultVocabulary.codingTerms).joined(separator: ", ")
        self.replacementsText = ReplacementRules.format(s.textReplacements ?? DefaultVocabulary.defaultReplacements)
        self.inputDevices = AudioDevices.inputDevices()
        refreshMicVolume()
    }

    // MARK: Mic input volume

    /// Re-read the hardware level for the currently selected device (call when the
    /// mic selection changes — different devices have different volumes).
    func refreshMicVolume() {
        micVolume = MicVolumeService.resolveDevice(uid: draft.selectedMicrophoneId)
            .flatMap { MicVolumeService.volume(for: $0) }
    }

    /// Applies immediately (hardware setting, not part of the draft/save cycle).
    func setMicVolume(_ value: Float) {
        micVolume = value
        guard let device = MicVolumeService.resolveDevice(uid: draft.selectedMicrophoneId) else { return }
        if !MicVolumeService.setVolume(value, for: device) {
            Log.warning("Mic volume: device \(device) rejected write")
        }
    }

    // MARK: Save / cancel

    func save() {
        draft.customVocabulary = vocabularyText
            .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        draft.textReplacements = ReplacementRules.parse(replacementsText)
        // Persist the key BEFORE onApply() (which reloads the model + re-checks the key).
        // Typed value → replace; "Remove" → clear; left blank → keep the existing key.
        let typed = openRouterKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty {
            KeychainService.setOpenRouterKey(typed)
        } else if removeKeyRequested {
            KeychainService.setOpenRouterKey(nil)
        }
        openRouterKey = ""
        removeKeyRequested = false
        hasStoredKey = KeychainService.hasOpenRouterKey
        store.replace(draft)
        onApply()
        stopTest()
        stopRecordingHotkey()
    }

    /// Mark the stored key for removal on the next Save (no Keychain read needed).
    func removeOpenRouterKey() {
        removeKeyRequested = true
        hasStoredKey = false
        openRouterKey = ""
    }

    func cancel() {
        stopTest()
        stopRecordingHotkey()
    }

    // MARK: Accessibility (for auto-paste)

    /// Begin watching Accessibility status; refreshes when the app regains focus
    /// (so granting it in System Settings updates the indicator on return).
    func startPermissionWatch() {
        refreshPermissions()
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshPermissions() }
        }
    }

    func stopPermissionWatch() {
        if let o = activeObserver { NotificationCenter.default.removeObserver(o); activeObserver = nil }
    }

    private func refreshPermissions() { accessibilityGranted = PermissionsService.hasAccessibility }

    /// Prompt for Accessibility and open the pane so the user can flip it on.
    func grantAccessibility() {
        PermissionsService.requestAccessibility()
        PermissionsService.openAccessibilitySettings()
    }

    // MARK: Hotkey recorder (local monitor — no special permission while window is key)

    func startRecordingHotkey() {
        recordingHotkey = true
        hotkeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let mods = self.modifiers(from: event.modifierFlags)
            // Require at least one modifier; ignore bare keys (e.g. plain Esc cancels recording).
            if event.keyCode == 53 { self.stopRecordingHotkey(); return nil }   // Esc aborts capture
            guard !mods.isEmpty else { return nil }
            self.draft.hotkey = HotkeyConfig(keyCode: UInt32(event.keyCode), modifiers: mods)
            self.stopRecordingHotkey()
            return nil
        }
    }

    func stopRecordingHotkey() {
        recordingHotkey = false
        if let m = hotkeyMonitor { NSEvent.removeMonitor(m); hotkeyMonitor = nil }
    }

    private func modifiers(from flags: NSEvent.ModifierFlags) -> HotkeyModifiers {
        var m: HotkeyModifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        if flags.contains(.shift) { m.insert(.shift) }
        return m
    }

    // MARK: Mic test

    func toggleTest() { testing ? stopTest() : startTest() }

    private func startTest() {
        PermissionsService.requestMicrophone { [weak self] granted in
            guard let self, granted else { self?.testStatus = "Microphone access needed"; return }
            self.testCapture.onLevel = { [weak self] level in
                guard let self else { return }
                self.testLevel = level
                let pct = Int(level * 100)
                if level < 0.02 { self.testStatus = "No audio detected" }
                else if level < 0.15 { self.testStatus = "Low level (\(pct)%)" }
                else { self.testStatus = "Microphone OK — \(pct)%" }
            }
            let deviceID = self.draft.selectedMicrophoneId.flatMap { AudioDevices.device(forUID: $0)?.id }
            do { try self.testCapture.start(deviceID: deviceID); self.testing = true; self.testStatus = "Listening…" }
            catch { self.testStatus = "Couldn't start mic" }
        }
    }

    private func stopTest() {
        guard testing else { return }
        _ = testCapture.stop()
        testing = false
        testLevel = 0
    }

    func resetVocabulary() {
        vocabularyText = DefaultVocabulary.codingTerms.joined(separator: ", ")
        replacementsText = ReplacementRules.format(DefaultVocabulary.defaultReplacements)
    }

    /// Rules the editor currently parses to (malformed lines don't count).
    var replacementCount: Int { ReplacementRules.parse(replacementsText).count }

    func openModelsFolder() {
        try? FileManager.default.createDirectory(at: AppPaths.modelsDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(AppPaths.modelsDir)
    }
}

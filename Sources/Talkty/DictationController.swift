import AppKit
import TalktyKit

/// The recording state machine. Wires the global hotkey to: capture → whisper →
/// post-process → clipboard/auto-paste → overlay + history. Ported from the
/// Windows MainViewModel/MainWindow orchestration.
@MainActor
final class DictationController {
    private let state: AppState
    private let settings: SettingsStore
    private let history: HistoryStore
    private let overlay: OverlayController

    private let audio = AudioCaptureService()
    let transcription = TranscriptionService()
    private let promptRefiner = PromptRefinementService()
    private let clipboard = ClipboardService()
    private let autoPaste = AutoPasteService()
    private let ducking = VolumeDuckingService()
    let hotkey = HotkeyService()

    private var timer: Timer?
    private var startedAt: Date?
    private var resetWork: DispatchWorkItem?
    /// When the last successful auto-paste landed, and whether the current take began
    /// soon enough after it to count as continuous dictation (→ prepend a space).
    private var lastPasteAt: Date?
    private var continuesPreviousTake = false

    init(state: AppState, settings: SettingsStore, history: HistoryStore, overlay: OverlayController) {
        self.state = state
        self.settings = settings
        self.history = history
        self.overlay = overlay

        audio.onLevel = { [weak self] level in self?.state.audioLevel = level }
        hotkey.onKeyDown = { [weak self] in self?.handleKeyDown() }
        hotkey.onKeyUp = { [weak self] in self?.handleKeyUp() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
    }

    // MARK: Hotkey

    func registerHotkey() {
        hotkey.pushToTalk = settings.settings.pushToTalk
        if !hotkey.registerToggle(settings.settings.hotkey) {
            Log.warning("Failed to register hotkey \(settings.settings.hotkey.displayString)")
        }
    }
    func updateHotkey(_ config: HotkeyConfig) {
        settings.update { $0.hotkey = config }
        hotkey.pushToTalk = settings.settings.pushToTalk
        hotkey.registerToggle(config)
    }

    // MARK: Hotkey edges (toggle vs push-to-talk)

    private func handleKeyDown() {
        if settings.settings.pushToTalk { pttStart() } else { toggle() }
    }
    private func handleKeyUp() {
        if settings.settings.pushToTalk { pttStop() }
    }
    /// Push-to-talk: pressing the hotkey starts recording.
    private func pttStart() {
        switch state.recordingState {
        case .idle, .copied, .cancelled: startListening()
        case .noModel: NotificationCenter.default.post(name: .talktyOpenSettings, object: nil)
        default: break
        }
    }
    /// Push-to-talk: releasing the hotkey stops + transcribes.
    private func pttStop() {
        if state.recordingState == .listening { stopAndTranscribe() }
    }

    // MARK: Model

    func loadModel() {
        let spec = settings.settings.model
        guard spec.isDownloaded else {
            Log.warning("Load model: \(spec.id) not downloaded")
            state.recordingState = .noModel
            state.modelLoaded = false
            state.statusText = "No model"
            return
        }
        state.recordingState = .loadingModel
        state.statusText = spec.isCloud ? "Checking cloud key…" : "Loading model…"
        let useGPU = settings.settings.useGPU
        let transcription = self.transcription
        Log.info("Load model: \(spec.id) (gpu=\(useGPU))…")
        Task.detached(priority: .userInitiated) {
            let t0 = Date()
            let ok = transcription.loadModel(spec, useGPU: useGPU)
            let dt = -t0.timeIntervalSinceNow
            Log.info("Load model: \(ok ? "ready" : "FAILED") in \(String(format: "%.2f", dt))s (incl. warmup)")
            await MainActor.run { [weak self] in
                self?.state.modelLoaded = ok
                self?.state.recordingState = ok ? .idle : .noModel
                self?.state.statusText = ok ? "Ready"
                    : (spec.isCloud ? "Add OpenRouter API key in Settings" : "Model failed to load")
            }
        }
    }

    // MARK: Toggle / record

    func toggle() {
        Log.debug("Hotkey toggle (state=\(state.recordingState))")
        switch state.recordingState {
        case .listening: stopAndTranscribe()
        case .idle, .copied, .cancelled: startListening()
        case .noModel:
            Log.info("Toggle ignored: no model loaded → opening Settings")
            NotificationCenter.default.post(name: .talktyOpenSettings, object: nil)
        default: Log.debug("Toggle ignored in state=\(state.recordingState)")
        }
    }

    private func startListening() {
        guard state.modelLoaded else {
            Log.info("Start blocked: model not loaded → opening Settings")
            NotificationCenter.default.post(name: .talktyOpenSettings, object: nil)
            return
        }
        Log.info("▶ Dictation start requested")
        PermissionsService.requestMicrophone { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Log.warning("Microphone permission denied")
                self.notify("Microphone access needed", "Enable it in System Settings → Privacy → Microphone.")
                PermissionsService.openMicrophoneSettings()
                return
            }
            Log.debug("Microphone permission granted")
            self.beginCapture()
        }
    }

    private func beginCapture() {
        cancelPendingReset()   // a prior take's reset must not tear down this one
        continuesPreviousTake = lastPasteAt.map {
            Date().timeIntervalSince($0) < Constants.takeContinuationWindow
        } ?? false
        let s = settings.settings
        if s.duckVolumeWhileRecording {
            ducking.duck(to: s.volumeDuckLevel)
        }
        if s.soundFeedback { Sounds.start() }
        let deviceID = s.selectedMicrophoneId.flatMap { AudioDevices.device(forUID: $0)?.id }
        Log.info("Capture: mic=\(s.selectedMicrophoneId ?? "system default") "
            + "duck=\(s.duckVolumeWhileRecording ? "\(Int(s.volumeDuckLevel * 100))%" : "off")")
        do {
            try audio.start(deviceID: deviceID)
        } catch {
            Log.error("Failed to start capture: \(error)")
            notify("Couldn't start recording", "\(error.localizedDescription)")
            return
        }
        // Prompting is per-take: every recording starts with it OFF; the user toggles
        // the overlay sparkle on during the take if they want a refined agent prompt.
        state.promptingMode = false
        state.recordingState = .listening
        state.statusText = "Listening…"
        state.elapsed = 0
        startedAt = Date()
        hotkey.registerCancel()
        overlay.show(state: state)
        startTimer()
    }

    private func stopAndTranscribe() {
        Log.info("■ Stop requested after \(String(format: "%.1f", state.elapsed))s")
        stopTimer()
        hotkey.unregisterCancel()
        let take = audio.stop()   // cheap: raw buffer handoff, no resample/trim
        if settings.settings.duckVolumeWhileRecording {
            ducking.restore()
        }
        state.recordingState = .transcribing
        state.statusText = "Transcribing…"
        state.audioLevel = 0   // freeze the meter; we're no longer capturing

        let settingsSnapshot = settings.settings
        let transcription = self.transcription
        let promptRefiner = self.promptRefiner
        let promptMode = state.promptingMode   // captured for THIS take
        // Resample + trim + whisper all run off the main actor; only finish() hops back.
        Task.detached(priority: .userInitiated) { [weak self] in
            let samples = AudioCaptureService.finalize(take)
            let result = await transcription.transcribe(samples: samples, settings: settingsSnapshot)
            guard let self else { return }   // rebind: a weak `var` capture is a Swift 6 error in a @Sendable closure

            // Prompting: expand the dictation into a structured coding-agent prompt.
            // Fails safe — any miss keeps the raw transcription, never lost.
            var finalResult = result
            if promptMode, result.success, !result.text.isEmpty {
                if promptRefiner.isConfigured {
                    await MainActor.run { self.state.statusText = "Refining prompt…" }
                    if let refined = await promptRefiner.refine(result.text, primaryModel: settingsSnapshot.promptingModelId),
                       !refined.isEmpty {
                        Log.info("Prompt mode: expanded \(result.text.count) → \(refined.count) chars")
                        finalResult = TranscriptionResult(text: refined, duration: result.duration)
                    } else {
                        Log.warning("Prompt refinement returned nothing — using raw transcription")
                    }
                } else {
                    Log.warning("Prompt mode on but no OpenRouter key — skipping refinement")
                    await MainActor.run {
                        self.notify("Prompting needs a key",
                                    "Add your OpenRouter API key in Settings to use Prompting.")
                    }
                }
            }
            let toFinish = finalResult   // immutable copy for the @Sendable hop
            await MainActor.run { self.finish(toFinish) }
        }
    }

    private func finish(_ result: TranscriptionResult) {
        guard result.success, !result.text.isEmpty else {
            Log.info("Result: empty — \(result.errorMessage ?? "no speech detected")")
            state.statusText = result.errorMessage ?? "No speech detected"
            resetSoon()
            return
        }
        let text = result.text
        state.lastText = text
        let s = settings.settings
        Log.info("Result: \(text.count) chars in \(String(format: "%.2f", result.duration))s — \"\(Log.preview(text))\"")

        if s.copyToClipboard {
            clipboard.setText(text)
            Log.debug("Clipboard set (\(text.count) chars)")
        }
        if s.autoPaste {
            // Continuous dictation: separate this take from the previous one. Only the
            // typed text gets the space — the clipboard keeps the clean transcription.
            let pasteText = continuesPreviousTake ? " " + text : text
            switch autoPaste.insert(pasteText, keepOnClipboard: s.copyToClipboard ? text : nil) {
            case .pasted:
                lastPasteAt = Date()
                Log.info("Auto-paste: inserted \(pasteText.count) chars at cursor"
                    + (continuesPreviousTake ? " (continuation)" : ""))
            case .needsPermission:
                if !s.copyToClipboard { clipboard.setText(text) }   // fallback so ⌘V works
                Log.warning("Auto-paste: needs Accessibility — text on clipboard (⌘V to paste)")
                remindAccessibilityOnce()
            case .failed:
                if !s.copyToClipboard { clipboard.setText(text) }
                Log.error("Auto-paste: insert failed — text on clipboard")
            }
        }
        history.add(HistoryEntry(text: text, durationSeconds: result.duration))
        Log.debug("History: entry added")
        NotificationCenter.default.post(name: .talktyHistoryChanged, object: nil)

        state.recordingState = .copied
        state.statusText = "Copied"
        if s.soundFeedback { Sounds.done() }
        if s.showNotification { notify("Transcribed", text) }
        resetSoon()
    }

    func cancel() {
        guard state.recordingState == .listening else { return }
        Log.info("✕ Dictation cancelled (ESC)")
        if settings.settings.soundFeedback { Sounds.cancel() }
        stopTimer()
        hotkey.unregisterCancel()
        audio.cancel()
        if settings.settings.duckVolumeWhileRecording {
            ducking.restore()
        }
        state.recordingState = .cancelled
        state.statusText = "Cancelled"
        resetSoon()
    }

    // MARK: Timer + reset

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let startedAt = self.startedAt else { return }
                self.state.elapsed = Date().timeIntervalSince(startedAt)
            }
        }
    }
    private func stopTimer() { timer?.invalidate(); timer = nil }

    /// Cancel a queued reset so a finished take's teardown can't hide the overlay or
    /// clobber the status of a new take started within the reset delay.
    private func cancelPendingReset() {
        resetWork?.cancel()
        resetWork = nil
    }

    private func resetSoon() {
        cancelPendingReset()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.resetWork = nil
            // A new take started during the delay — leave it alone entirely.
            guard self.state.recordingState != .listening else { return }
            self.overlay.hide()
            self.state.recordingState = self.state.modelLoaded ? .idle : .noModel
            self.state.statusText = self.state.modelLoaded ? "Ready" : "No model"
            self.state.audioLevel = 0
        }
        resetWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.statusResetDelay, execute: work)
    }

    private func notify(_ title: String, _ body: String) {
        Notifications.show(title: title, body: body)
    }

    // MARK: Auto-paste permission

    /// If auto-paste is enabled without Accessibility, surface the system prompt
    /// (with its "Open System Settings" button). Called when settings are applied.
    func ensureAutoPastePermission() {
        guard settings.settings.autoPaste, !PermissionsService.hasAccessibility else { return }
        Log.info("Auto-paste enabled without Accessibility — prompting")
        PermissionsService.requestAccessibility()
    }

    /// One-time gentle nudge at paste time if Accessibility still isn't granted —
    /// the text is already on the clipboard, so ⌘V works as a fallback.
    private func remindAccessibilityOnce() {
        guard !settings.settings.hints.hasSeenAutoPasteHint else { return }
        settings.update { $0.hints.hasSeenAutoPasteHint = true }
        notify("Auto-paste needs Accessibility",
               "Enable Talkty in System Settings → Privacy & Security → Accessibility. Your text is on the clipboard — press ⌘V.")
        PermissionsService.openAccessibilitySettings()
    }
}

extension Notification.Name {
    static let talktyOpenSettings = Notification.Name("talktyOpenSettings")
    static let talktyHistoryChanged = Notification.Name("talktyHistoryChanged")
    static let talktyShowOnboarding = Notification.Name("talktyShowOnboarding")
}

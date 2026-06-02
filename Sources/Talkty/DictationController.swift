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
    private let clipboard = ClipboardService()
    private let autoPaste = AutoPasteService()
    private let ducking = VolumeDuckingService()
    let hotkey = HotkeyService()

    private var timer: Timer?
    private var startedAt: Date?

    init(state: AppState, settings: SettingsStore, history: HistoryStore, overlay: OverlayController) {
        self.state = state
        self.settings = settings
        self.history = history
        self.overlay = overlay

        audio.onLevel = { [weak self] level in self?.state.audioLevel = level }
        hotkey.onToggle = { [weak self] in self?.toggle() }
        hotkey.onCancel = { [weak self] in self?.cancel() }
    }

    // MARK: Hotkey

    func registerHotkey() {
        if !hotkey.registerToggle(settings.settings.hotkey) {
            Log.warning("Failed to register hotkey \(settings.settings.hotkey.displayString)")
        }
    }
    func updateHotkey(_ config: HotkeyConfig) {
        settings.update { $0.hotkey = config }
        hotkey.registerToggle(config)
    }

    // MARK: Model

    func loadModel() {
        let spec = settings.settings.model
        guard spec.isDownloaded else {
            state.recordingState = .noModel
            state.modelLoaded = false
            state.statusText = "No model"
            return
        }
        state.recordingState = .loadingModel
        state.statusText = "Loading model…"
        let useGPU = settings.settings.useGPU
        let transcription = self.transcription
        Task.detached(priority: .userInitiated) {
            let ok = transcription.loadModel(spec, useGPU: useGPU)
            await MainActor.run { [weak self] in
                self?.state.modelLoaded = ok
                self?.state.recordingState = ok ? .idle : .noModel
                self?.state.statusText = ok ? "Ready" : "Model failed to load"
            }
        }
    }

    // MARK: Toggle / record

    func toggle() {
        switch state.recordingState {
        case .listening: stopAndTranscribe()
        case .idle, .copied, .cancelled: startListening()
        case .noModel:
            NotificationCenter.default.post(name: .talktyOpenSettings, object: nil)
        default: break   // loading / transcribing → ignore
        }
    }

    private func startListening() {
        guard state.modelLoaded else {
            NotificationCenter.default.post(name: .talktyOpenSettings, object: nil)
            return
        }
        PermissionsService.requestMicrophone { [weak self] granted in
            guard let self else { return }
            guard granted else {
                Log.warning("Microphone permission denied")
                self.notify("Microphone access needed", "Enable it in System Settings → Privacy → Microphone.")
                PermissionsService.openMicrophoneSettings()
                return
            }
            self.beginCapture()
        }
    }

    private func beginCapture() {
        let s = settings.settings
        if s.duckVolumeWhileRecording {
            let level = s.volumeDuckLevel
            let ducking = self.ducking
            DispatchQueue.global(qos: .userInitiated).async { ducking.duck(to: level) }
        }
        let deviceID = s.selectedMicrophoneId.flatMap { AudioDevices.device(forUID: $0)?.id }
        do {
            try audio.start(deviceID: deviceID)
        } catch {
            Log.error("Failed to start capture: \(error)")
            notify("Couldn't start recording", "\(error.localizedDescription)")
            return
        }
        state.recordingState = .listening
        state.statusText = "Listening…"
        state.elapsed = 0
        startedAt = Date()
        hotkey.registerCancel()
        overlay.show(state: state)
        startTimer()
    }

    private func stopAndTranscribe() {
        stopTimer()
        hotkey.unregisterCancel()
        let samples = audio.stop()
        if settings.settings.duckVolumeWhileRecording {
            let ducking = self.ducking
            DispatchQueue.global(qos: .userInitiated).async { ducking.restore() }
        }
        state.recordingState = .transcribing
        state.statusText = "Transcribing…"

        let settingsSnapshot = settings.settings
        Task { [weak self] in
            guard let self else { return }
            let result = await self.transcription.transcribe(samples: samples, settings: settingsSnapshot)
            self.finish(result)
        }
    }

    private func finish(_ result: TranscriptionResult) {
        guard result.success, !result.text.isEmpty else {
            state.statusText = result.errorMessage ?? "No speech detected"
            resetSoon()
            return
        }
        let text = result.text
        state.lastText = text
        let s = settings.settings

        let previousClipboard = clipboard.snapshot()
        if s.copyToClipboard || s.autoPaste {
            clipboard.setText(text)
        }
        if s.autoPaste {
            autoPaste.waitForModifiersRelease()
            let pasted = autoPaste.paste()
            if pasted && !s.copyToClipboard {
                // Restore the user's clipboard shortly after the paste lands.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    self.clipboard.restore(previousClipboard)
                }
            }
        }
        history.add(HistoryEntry(text: text, durationSeconds: result.duration))
        NotificationCenter.default.post(name: .talktyHistoryChanged, object: nil)

        state.recordingState = .copied
        state.statusText = "Copied"
        if s.showNotification { notify("Transcribed", text) }
        resetSoon()
    }

    func cancel() {
        guard state.recordingState == .listening else { return }
        stopTimer()
        hotkey.unregisterCancel()
        audio.cancel()
        if settings.settings.duckVolumeWhileRecording {
            let ducking = self.ducking
            DispatchQueue.global(qos: .userInitiated).async { ducking.restore() }
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

    private func resetSoon() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.statusResetDelay) { [weak self] in
            guard let self else { return }
            self.overlay.hide()
            if self.state.recordingState != .listening {
                self.state.recordingState = self.state.modelLoaded ? .idle : .noModel
                self.state.statusText = self.state.modelLoaded ? "Ready" : "No model"
                self.state.audioLevel = 0
            }
        }
    }

    private func notify(_ title: String, _ body: String) {
        Notifications.show(title: title, body: body)
    }
}

extension Notification.Name {
    static let talktyOpenSettings = Notification.Name("talktyOpenSettings")
    static let talktyHistoryChanged = Notification.Name("talktyHistoryChanged")
    static let talktyShowOnboarding = Notification.Name("talktyShowOnboarding")
}

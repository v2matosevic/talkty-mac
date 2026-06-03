import SwiftUI
import TalktyKit

struct SettingsView: View {
    @ObservedObject var vm: SettingsViewModel
    @ObservedObject var models: ModelManager
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                SettingsSections(vm: vm, models: models).padding(20)
            }
            footer
        }
        .frame(width: 440, height: 720)
        .background(Theme.bg)
        .onAppear { models.refresh() }
    }

    private var header: some View {
        HStack {
            Text("Settings").font(.system(size: 16, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Spacer()
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.bg)
    }

    private var footer: some View {
        HStack {
            Spacer()
            SecondaryButton(title: "Cancel") { vm.cancel(); onCancel() }
            PrimaryButton(title: "Save") { vm.save(); onSave() }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Theme.card.opacity(0.5))
        .overlay(Rectangle().frame(height: 1).foregroundStyle(Theme.border), alignment: .top)
    }
}

/// The scrollable section stack (separated so it renders without a ScrollView).
struct SettingsSections: View {
    @ObservedObject var vm: SettingsViewModel
    @ObservedObject var models: ModelManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            modelSection
            microphoneSection
            languageSection
            behaviorSection
            vocabularySection
            shortcutSection
        }
    }

    // MARK: Models

    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Model")
            ForEach(ModelTier.allCases, id: \.self) { tier in
                let specs = ModelCatalog.models(in: tier)
                if !specs.isEmpty {
                    Text(tier.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.textMuted)
                    Card {
                        VStack(spacing: 0) {
                            ForEach(Array(specs.enumerated()), id: \.element.id) { idx, spec in
                                ModelRow(spec: spec, selectedId: $vm.draft.modelId, models: models)
                                if idx < specs.count - 1 {
                                    Divider().background(Theme.border).padding(.vertical, 8)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Microphone

    private var microphoneSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Microphone")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("", selection: micBinding) {
                        Text("System Default").tag(String?.none)
                        ForEach(vm.inputDevices) { d in Text(d.name).tag(String?.some(d.uid)) }
                    }
                    .labelsHidden().pickerStyle(.menu).tint(Theme.textPrimary)

                    HStack(spacing: 10) {
                        Button { vm.toggleTest() } label: {
                            Text(vm.testing ? "Stop" : "Test").font(.system(size: 12, weight: .medium))
                                .foregroundStyle(Theme.textPrimary)
                                .padding(.horizontal, 16).padding(.vertical, 7)
                                .background(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
                        }.buttonStyle(.plain)
                        LevelBar(fraction: Double(vm.testLevel), color: Theme.green, height: 8)
                    }
                    if !vm.testStatus.isEmpty {
                        Text(vm.testStatus).font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                    }
                }
            }
        }
    }
    private var micBinding: Binding<String?> {
        Binding(get: { vm.draft.selectedMicrophoneId }, set: { vm.draft.selectedMicrophoneId = $0 })
    }

    // MARK: Language

    private var languageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Language")
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    Picker("", selection: $vm.draft.language) {
                        ForEach(Languages.all) { lang in Text(lang.name).tag(lang.code) }
                    }.labelsHidden().pickerStyle(.menu).tint(Theme.textPrimary)
                    if !ModelCatalog.spec(for: vm.draft.modelId).multilingual {
                        Text("The selected model is English-only; transcription uses English.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                    }
                }
            }
        }
    }

    // MARK: Behavior

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Behavior")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CheckRow(label: "Copy to clipboard", isOn: $vm.draft.copyToClipboard)
                    CheckRow(label: "Auto-paste at cursor", isOn: $vm.draft.autoPaste,
                             subtitle: "Requires Accessibility permission")
                    CheckRow(label: "Show notification", isOn: $vm.draft.showNotification)
                    CheckRow(label: "Launch at login", isOn: $vm.draft.launchAtLogin,
                             subtitle: "Start Talkty automatically when you log in")
                    CheckRow(label: "Lower volume while recording", isOn: $vm.draft.duckVolumeWhileRecording)
                    if vm.draft.duckVolumeWhileRecording {
                        HStack {
                            Text("Volume").font(.system(size: 12)).foregroundStyle(Theme.textMuted)
                            Stepper(value: $vm.draft.volumeDuckLevel, in: 0.05...1.0, step: 0.05) {
                                Text("\(Int(vm.draft.volumeDuckLevel * 100))%")
                                    .font(Theme.mono(12)).foregroundStyle(Theme.textPrimary)
                            }
                        }
                    }
                    Divider().background(Theme.border)
                    CheckRow(label: "Metal GPU acceleration", isOn: $vm.draft.useGPU,
                             subtitle: "Recommended on Apple Silicon")
                }
            }
        }
    }

    // MARK: Vocabulary

    private var vocabularySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Vocabulary")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    CheckRow(label: "Use custom vocabulary", isOn: $vm.draft.useCustomVocabulary,
                             subtitle: "Biases Whisper toward your terms")
                    if vm.draft.useCustomVocabulary {
                        Text("Terms (comma-separated)").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        TextEditor(text: $vm.vocabularyText)
                            .font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                            .scrollContentBackground(.hidden)
                            .frame(height: 70)
                            .padding(6)
                            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.border, lineWidth: 1))
                        HStack {
                            Text("\(vm.replacementRows.count) replacements")
                                .font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                            Spacer()
                            Button("Reset to defaults") { vm.resetVocabulary() }
                                .buttonStyle(.plain)
                                .font(.system(size: 11)).foregroundStyle(Theme.purple)
                        }
                    }
                }
            }
        }
    }

    // MARK: Shortcut

    private var shortcutSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel(text: "Shortcut")
            Card {
                HStack {
                    Text("Toggle recording").font(.system(size: 13)).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Button { vm.recordingHotkey ? vm.stopRecordingHotkey() : vm.startRecordingHotkey() } label: {
                        Text(vm.recordingHotkey ? "Press keys…" : vm.draft.hotkey.displayString)
                            .font(Theme.mono(12, .semibold))
                            .foregroundStyle(vm.recordingHotkey ? Theme.purple : Theme.textPrimary)
                            .padding(.horizontal, 12).padding(.vertical, 6)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Theme.bg))
                            .overlay(RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(vm.recordingHotkey ? Theme.purple : Theme.border, lineWidth: 1))
                    }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// A single model row: name, badges, size, and a select/download/progress control.
private struct ModelRow: View {
    let spec: ModelSpec
    @Binding var selectedId: String
    @ObservedObject var models: ModelManager

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selectedId == spec.id ? "largecircle.fill.circle" : "circle")
                .font(.system(size: 15))
                .foregroundStyle(selectedId == spec.id ? Theme.purple : Theme.textFaint)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(spec.displayName).font(.system(size: 13, weight: .medium)).foregroundStyle(Theme.textPrimary)
                    if spec.recommended { Pill(text: "Recommended", color: Theme.green) }
                    if spec.multilingual { Pill(text: "Multilingual", color: Theme.purple) }
                }
                Text("\(spec.detail)  ·  \(spec.sizeDisplay)").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            }
            Spacer()
            control
        }
        .contentShape(Rectangle())
        .onTapGesture { if models.isDownloaded(spec.id) { selectedId = spec.id } }
    }

    @ViewBuilder private var control: some View {
        switch models.states[spec.id] {
        case .downloading(let p):
            VStack(alignment: .trailing, spacing: 3) {
                LevelBar(fraction: p.fraction, color: Theme.purple, height: 5).frame(width: 70)
                Text("\(Int(p.fraction * 100))%").font(Theme.mono(10)).foregroundStyle(Theme.textMuted)
            }
            Button { models.cancel(spec.id) } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.textFaint)
            }.buttonStyle(.plain)
        default:
            if models.isDownloaded(spec.id) {
                Pill(text: "Downloaded", color: Theme.green)
            } else {
                Button { models.download(spec) } label: {
                    Image(systemName: "arrow.down.circle").font(.system(size: 16)).foregroundStyle(Theme.purple)
                }.buttonStyle(.plain)
            }
        }
    }
}

import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers
import TalktyKit

/// Backs the main window's history list, reloading on transcription changes.
@MainActor
final class MainViewModel: ObservableObject {
    @Published var history: [HistoryEntry] = []
    @Published var searchText = ""
    /// Id of the entry whose copy just succeeded, for a brief "Copied" flash.
    @Published var copiedId: UUID?
    private let store: HistoryStore
    private let clipboard = ClipboardService()
    private var observer: NSObjectProtocol?
    private var copiedReset: DispatchWorkItem?

    init(history store: HistoryStore) {
        self.store = store
        self.history = store.entries
        observer = NotificationCenter.default.addObserver(
            forName: .talktyHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.history = store.entries }
        }
    }

    /// History filtered by the search box (case-insensitive substring, both halves of a prompt entry).
    var filtered: [HistoryEntry] {
        let q = searchText.trimmingCharacters(in: .whitespaces)
        return q.isEmpty ? history : history.filter {
            $0.text.localizedCaseInsensitiveContains(q) || ($0.rawTranscription?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// Copy the entry's text (the generated prompt for a Prompting take). Only a
    /// successful pasteboard write shows the "Copied" flash.
    func copy(_ entry: HistoryEntry) { copy(entry.text, id: entry.id) }
    /// Copy the words as spoken (Prompting takes only).
    func copyRaw(_ entry: HistoryEntry) {
        guard let raw = entry.rawTranscription else { return }
        copy(raw, id: entry.id)
    }
    private func copy(_ text: String, id: UUID) {
        guard clipboard.setText(text) else {
            Log.warning("History: clipboard write failed")
            return
        }
        copiedId = id
        copiedReset?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.copiedId = nil }
        copiedReset = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: work)
    }

    func delete(_ entry: HistoryEntry) {
        store.remove(id: entry.id)
        history = store.entries
    }
    func clearHistory() { store.clear(); history = []; searchText = "" }

    /// Export the full history to a user-chosen .txt file, newest first.
    func export() {
        guard !history.isEmpty else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "talkty-history.txt"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let body = history.map { entry in
            var line = "[\(f.string(from: entry.timestamp))]  \(entry.text)"
            if let raw = entry.rawTranscription { line += "\n    (you said) \(raw)" }
            return line
        }.joined(separator: "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}

@MainActor
final class MainWindowController {
    private let window: NSWindow
    init(state: AppState, history: HistoryStore,
         onToggle: @escaping () -> Void, onSettings: @escaping () -> Void) {
        let vm = MainViewModel(history: history)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 460),
                          styleMask: [.titled, .closable, .fullSizeContentView],
                          backing: .buffered, defer: false)
        window.title = "Talkty"
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(Theme.bg)
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = NSHostingView(rootView:
            MainView(state: state, vm: vm, onToggle: onToggle, onSettings: onSettings))
    }
    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
}

struct MainView: View {
    @ObservedObject var state: AppState
    @ObservedObject var vm: MainViewModel
    let onToggle: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            if let update = state.updateAvailable { updateBanner(update) }
            recordArea
            Divider().background(Theme.border)
            historyArea
        }
        .frame(width: 380, height: 460)
        .background(Theme.bg)
    }

    private var titleBar: some View {
        HStack {
            Text("Talkty").font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.textMuted)
            Spacer()
            Button(action: onSettings) {
                Image(systemName: "gearshape").font(.system(size: 14)).foregroundStyle(Theme.textMuted)
            }.buttonStyle(.plain)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 8)
    }

    private func updateBanner(_ update: UpdateInfo) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill").foregroundStyle(Theme.green)
            Text("Update available: v\(update.latestVersion)").font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
            Spacer()
            Button("Download") { if let u = URL(string: update.downloadURL) { NSWorkspace.shared.open(u) } }
                .buttonStyle(.plain).font(.system(size: 12, weight: .medium)).foregroundStyle(Theme.green)
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(LinearGradient(colors: [Color(hex: 0x1A3730), Color(hex: 0x1A2F30)],
                                   startPoint: .leading, endPoint: .trailing))
    }

    private var recordArea: some View {
        VStack(spacing: 14) {
            Button(action: onToggle) {
                ZStack {
                    Circle().strokeBorder(state.accent.opacity(0.25), lineWidth: 2).frame(width: 64, height: 64)
                    Circle().fill(state.accent).frame(width: dotSize, height: dotSize)
                        .animation(.spring(response: 0.3), value: state.recordingState)
                }
            }.buttonStyle(.plain)
            Text(statusText).font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(state.recordingState == .noModel ? "Open Settings to download a model" : "Press \(state.hotkeyDisplay) anywhere")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            LevelBar(fraction: Double(state.audioLevel),
                     color: state.recordingState == .listening ? Theme.red : Theme.green, height: 3)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 22)
    }

    private var historyArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                Text("HISTORY").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textFaint)
                Spacer()
                if !vm.history.isEmpty {
                    Button("Export") { vm.export() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                    Button("Clear") { vm.clearHistory() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)

            if !vm.history.isEmpty { searchField }

            if vm.history.isEmpty {
                Text("Your transcriptions will appear here. Press \(state.hotkeyDisplay) to start.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.filtered.isEmpty {
                Text("No matches.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.filtered) { entry in
                            HistoryRow(entry: entry, copied: vm.copiedId == entry.id,
                                       onCopy: { vm.copy(entry) },
                                       onCopyRaw: { vm.copyRaw(entry) },
                                       onDelete: { vm.delete(entry) })
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
            TextField("Search transcriptions", text: $vm.searchText)
                .textFieldStyle(.plain).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
            if !vm.searchText.isEmpty {
                Button { vm.searchText = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                }.buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7).fill(Theme.card))
        .padding(.horizontal, 20).padding(.bottom, 6)
    }

    private var dotSize: CGFloat { state.recordingState == .listening ? 28 : 20 }
    private var statusText: String {
        switch state.recordingState {
        case .idle, .copied, .cancelled: return "Ready to Record"
        case .listening: return "Recording…"
        case .transcribing: return state.promptingMode ? "Prompting…" : "Transcribing…"
        case .loadingModel: return "Loading Model…"
        case .failed: return state.statusText
        case .noModel: return "No Model Loaded"
        }
    }
}

/// One history row. Click copies the text; a Prompting take shows a PROMPT badge and
/// the words as spoken on a second line (click that line to copy just those). Hover
/// reveals delete.
private struct HistoryRow: View {
    let entry: HistoryEntry
    let copied: Bool
    let onCopy: () -> Void
    let onCopyRaw: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Button(action: onCopy) {
                    HStack(spacing: 6) {
                        if entry.isPrompt { Pill(text: "PROMPT", color: Theme.purple) }
                        Text(entry.text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                            .lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }.buttonStyle(.plain)
                if copied {
                    Text("Copied").font(.system(size: 10, weight: .medium)).foregroundStyle(Theme.green)
                } else if hovering {
                    Button(action: onDelete) {
                        Image(systemName: "trash").font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                    }.buttonStyle(.plain).help("Delete this entry")
                } else {
                    Text(timeString(entry.timestamp)).font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                }
            }
            if let raw = entry.rawTranscription {
                Button(action: onCopyRaw) {
                    Text("You said: \(raw)").font(.system(size: 11)).foregroundStyle(Theme.textMuted)
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).help("Copy the words as spoken")
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 9)
        .background(hovering ? Theme.card : Color.clear)
        .onHover { hovering = $0 }
    }

    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}

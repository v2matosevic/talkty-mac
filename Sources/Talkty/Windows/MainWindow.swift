import AppKit
import SwiftUI
import Combine
import TalktyKit

/// Backs the main window's history list, reloading on transcription changes.
@MainActor
final class MainViewModel: ObservableObject {
    @Published var history: [HistoryEntry] = []
    private let store: HistoryStore
    private var observer: NSObjectProtocol?

    init(history store: HistoryStore) {
        self.store = store
        self.history = store.entries
        observer = NotificationCenter.default.addObserver(
            forName: .talktyHistoryChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.history = store.entries }
        }
    }

    func copy(_ entry: HistoryEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.text, forType: .string)
    }
    func clearHistory() { store.clear(); history = [] }
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
            Text(state.recordingState == .noModel ? "Open Settings to download a model" : "Press \(hotkeyBadge) anywhere")
                .font(.system(size: 11)).foregroundStyle(Theme.textMuted)
            LevelBar(fraction: Double(state.audioLevel),
                     color: state.recordingState == .listening ? Theme.red : Theme.green, height: 3)
                .padding(.horizontal, 40)
        }
        .padding(.vertical, 22)
    }

    private var historyArea: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("HISTORY").font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(Theme.textFaint)
                Spacer()
                if !vm.history.isEmpty {
                    Button("Clear") { vm.clearHistory() }
                        .buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(Theme.textFaint)
                }
            }
            .padding(.horizontal, 20).padding(.top, 12).padding(.bottom, 6)

            if vm.history.isEmpty {
                Text("Your transcriptions will appear here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textFaint)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(vm.history) { entry in
                            Button { vm.copy(entry) } label: {
                                HStack {
                                    Text(entry.text).font(.system(size: 12)).foregroundStyle(Theme.textPrimary)
                                        .lineLimit(1).truncationMode(.tail)
                                    Spacer()
                                    Text(timeString(entry.timestamp)).font(Theme.mono(10)).foregroundStyle(Theme.textFaint)
                                }
                                .padding(.horizontal, 20).padding(.vertical, 9)
                                .contentShape(Rectangle())
                            }.buttonStyle(HoverRowStyle())
                        }
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
    }

    private var dotSize: CGFloat { state.recordingState == .listening ? 28 : 20 }
    private var hotkeyBadge: String { "⌥Q" }   // reflects default; live value shown in Settings
    private var statusText: String {
        switch state.recordingState {
        case .idle, .copied, .cancelled: return "Ready to Record"
        case .listening: return "Recording…"
        case .transcribing: return "Transcribing…"
        case .loadingModel: return "Loading Model…"
        case .noModel: return "No Model Loaded"
        }
    }
    private func timeString(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"; return f.string(from: d)
    }
}

private struct HoverRowStyle: ButtonStyle {
    @State private var hovering = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(hovering ? Theme.card : Color.clear)
            .onHover { hovering = $0 }
    }
}

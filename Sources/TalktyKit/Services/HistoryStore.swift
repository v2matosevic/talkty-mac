import Foundation

/// Transcription history (history.json), newest-first, capped at maxHistoryEntries.
/// Main-actor: entries backs UI lists and every caller (dictation finish, view
/// models, app delegate) already lives there; disk writes hop to ioQueue internally.
@MainActor
public final class HistoryStore {
    public private(set) var entries: [HistoryEntry]
    private let url = AppPaths.historyFile
    private let encoder = JSONEncoder()   // reused; only ever touched on ioQueue
    /// Persistence runs off the caller's thread: add() fires on the main actor at
    /// the end of every dictation and the in-memory array is the source of truth.
    private let ioQueue = DispatchQueue(label: "hr.version2.talkty.history", qos: .utility)

    public init() {
        if let data = try? Data(contentsOf: url),
           let loaded = try? JSONDecoder().decode([HistoryEntry].self, from: data) {
            entries = Array(loaded.prefix(Constants.maxHistoryEntries))
        } else {
            entries = []
        }
    }

    public func add(_ entry: HistoryEntry) {
        entries.insert(entry, at: 0)
        if entries.count > Constants.maxHistoryEntries {
            entries = Array(entries.prefix(Constants.maxHistoryEntries))
        }
        save()
    }

    public func remove(id: UUID) {
        entries.removeAll { $0.id == id }
        save()
    }

    public func clear() {
        entries = []
        save()
    }

    private func save() {
        let snapshot = entries
        ioQueue.async { [encoder, url] in
            do {
                let data = try encoder.encode(snapshot)
                try data.write(to: url, options: .atomic)
            } catch {
                Log.error("Failed to save history: \(error)")
            }
        }
    }

    /// Drain any pending write. Call before _exit(0) at quit so the last take's
    /// entry isn't lost.
    public func flush() {
        ioQueue.sync {}
    }
}

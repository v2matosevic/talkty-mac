import Foundation

/// Transcription history (history.json), newest-first, capped at maxHistoryEntries.
public final class HistoryStore {
    public private(set) var entries: [HistoryEntry]
    private let url = AppPaths.historyFile

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

    public func clear() {
        entries = []
        save()
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(entries)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Failed to save history: \(error)")
        }
    }
}

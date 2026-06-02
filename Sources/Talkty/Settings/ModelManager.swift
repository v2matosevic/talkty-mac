import SwiftUI
import TalktyKit

/// UI-facing wrapper over ModelDownloadService: tracks per-model download state for
/// the settings list and refreshes the downloaded set.
@MainActor
final class ModelManager: ObservableObject {
    enum State: Equatable {
        case idle
        case downloading(DownloadProgress)
        case failed(String)
    }

    @Published var states: [String: State] = [:]
    @Published var downloadedIDs: Set<String> = []

    private let service = ModelDownloadService()
    private var tasks: [String: Task<Void, Never>] = [:]

    init() { refresh() }

    func refresh() {
        downloadedIDs = Set(ModelCatalog.all.filter { $0.isDownloaded }.map { $0.id })
    }

    func isDownloaded(_ id: String) -> Bool { downloadedIDs.contains(id) }

    func isDownloading(_ id: String) -> Bool {
        if case .downloading = states[id] { return true }
        return false
    }

    func download(_ spec: ModelSpec) {
        guard tasks[spec.id] == nil else { return }
        states[spec.id] = .downloading(DownloadProgress(bytesDownloaded: 0, totalBytes: spec.approxBytes,
                                                        bytesPerSecond: 0, retryAttempt: 0))
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.service.download(spec) { progress in
                    Task { @MainActor in self.states[spec.id] = .downloading(progress) }
                }
                await MainActor.run {
                    self.states[spec.id] = .idle
                    self.tasks[spec.id] = nil
                    self.refresh()
                }
            } catch {
                await MainActor.run {
                    self.states[spec.id] = .failed("\(error)")
                    self.tasks[spec.id] = nil
                }
            }
        }
        tasks[spec.id] = task
    }

    func cancel(_ id: String) {
        tasks[id]?.cancel()
        tasks[id] = nil
        states[id] = .idle
    }

    func delete(_ spec: ModelSpec) {
        service.deleteModel(spec)
        states[spec.id] = .idle
        refresh()
    }
}

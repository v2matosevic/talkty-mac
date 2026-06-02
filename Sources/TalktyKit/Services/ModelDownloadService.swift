import Foundation

public struct DownloadProgress: Equatable {
    public var bytesDownloaded: Int64
    public var totalBytes: Int64
    public var bytesPerSecond: Double
    public var retryAttempt: Int

    public init(bytesDownloaded: Int64, totalBytes: Int64, bytesPerSecond: Double, retryAttempt: Int) {
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
        self.bytesPerSecond = bytesPerSecond
        self.retryAttempt = retryAttempt
    }

    public var fraction: Double { totalBytes > 0 ? min(1, Double(bytesDownloaded) / Double(totalBytes)) : 0 }
    public var etaSeconds: Double? {
        guard bytesPerSecond > 0, totalBytes > bytesDownloaded else { return nil }
        return Double(totalBytes - bytesDownloaded) / bytesPerSecond
    }
}

/// Downloads ggml models with HTTP Range resume, bounded retries, and a 95%-size
/// validation (no strict hash — HuggingFace re-hashes). Ported from the Windows
/// ModelDownloadService; URLSession replaces HttpClient.
public final class ModelDownloadService: @unchecked Sendable {
    public enum DownloadError: Error, CustomStringConvertible {
        case badResponse(Int)
        case tooSmall(Int64, Int64)
        case cancelled
        public var description: String {
            switch self {
            case .badResponse(let c): return "Server returned HTTP \(c)"
            case .tooSmall(let got, let want): return "Incomplete download (\(got) of \(want) bytes)"
            case .cancelled: return "Download cancelled"
            }
        }
    }

    private let maxRetries = 5
    private let retryBaseDelay: TimeInterval = 2

    public init() {}

    /// Download `spec` to its final location, reporting progress. Resumes from a
    /// `.part` file if present. Throws on repeated failure or cancellation.
    public func download(_ spec: ModelSpec,
                         progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let dest = spec.localURL
        let part = dest.appendingPathExtension("part")
        guard let url = URL(string: spec.url) else { throw DownloadError.badResponse(0) }

        var attempt = 0
        while true {
            do {
                try await attemptDownload(url: url, part: part, expected: spec.approxBytes,
                                          attempt: attempt, progress: progress)
                break
            } catch is CancellationError {
                throw DownloadError.cancelled
            } catch {
                attempt += 1
                Log.warning("Download attempt \(attempt) failed for \(spec.id): \(error)")
                if attempt >= maxRetries { throw error }
                try await Task.sleep(nanoseconds: UInt64(retryBaseDelay * Double(attempt) * 1_000_000_000))
            }
        }

        // Validate (95% threshold) and move into place.
        let size = (try? FileManager.default.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0
        guard size >= Int64(Double(spec.approxBytes) * 0.95) else {
            throw DownloadError.tooSmall(size, spec.approxBytes)
        }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: part, to: dest)
        Log.info("Model downloaded: \(spec.id) (\(size) bytes)")
    }

    public func deleteModel(_ spec: ModelSpec) {
        try? FileManager.default.removeItem(at: spec.localURL)
        try? FileManager.default.removeItem(at: spec.localURL.appendingPathExtension("part"))
    }

    private func attemptDownload(url: URL, part: URL, expected: Int64,
                                 attempt: Int,
                                 progress: @escaping @Sendable (DownloadProgress) -> Void) async throws {
        let fm = FileManager.default
        var existing: Int64 = (try? fm.attributesOfItem(atPath: part.path)[.size] as? Int64) ?? 0

        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        if existing > 0 { request.setValue("bytes=\(existing)-", forHTTPHeaderField: "Range") }

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 4 * 3600
        let session = URLSession(configuration: config)

        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw DownloadError.badResponse(0) }

        // Determine total + whether the server honored the range request.
        var total = expected
        if let len = http.value(forHTTPHeaderField: "Content-Length"), let n = Int64(len) {
            total = http.statusCode == 206 ? existing + n : n
        }
        let handle: FileHandle
        if http.statusCode == 206, existing > 0 {
            handle = try FileHandle(forWritingTo: part)
            try handle.seekToEnd()
        } else {
            // 200 (no resume) — start fresh.
            existing = 0
            fm.createFile(atPath: part.path, contents: nil)
            handle = try FileHandle(forWritingTo: part)
        }
        guard http.statusCode == 200 || http.statusCode == 206 else {
            try? handle.close(); throw DownloadError.badResponse(http.statusCode)
        }
        defer { try? handle.close() }

        var downloaded = existing
        let started = Date()
        var buffer = Data(); buffer.reserveCapacity(1 << 18)
        var lastReport = Date.distantPast

        for try await byte in bytes {
            try Task.checkCancellation()
            buffer.append(byte)
            if buffer.count >= (1 << 18) {
                try handle.write(contentsOf: buffer)
                downloaded += Int64(buffer.count)
                buffer.removeAll(keepingCapacity: true)
                let now = Date()
                if now.timeIntervalSince(lastReport) > 0.2 {
                    lastReport = now
                    let speed = Double(downloaded - existing) / max(now.timeIntervalSince(started), 0.001)
                    progress(DownloadProgress(bytesDownloaded: downloaded, totalBytes: total,
                                              bytesPerSecond: speed, retryAttempt: attempt))
                }
            }
        }
        if !buffer.isEmpty {
            try handle.write(contentsOf: buffer)
            downloaded += Int64(buffer.count)
        }
        let speed = Double(downloaded - existing) / max(Date().timeIntervalSince(started), 0.001)
        progress(DownloadProgress(bytesDownloaded: downloaded, totalBytes: total,
                                  bytesPerSecond: speed, retryAttempt: attempt))
    }
}

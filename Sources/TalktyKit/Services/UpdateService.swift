import Foundation

public struct UpdateInfo: Equatable {
    public let latestVersion: String
    public let downloadURL: String
    public let releaseNotes: String
    public init(latestVersion: String, downloadURL: String, releaseNotes: String) {
        self.latestVersion = latestVersion
        self.downloadURL = downloadURL
        self.releaseNotes = releaseNotes
    }
}

/// Background update check: fetches version.json from the GitHub raw feed and
/// compares against the running version (semantic, numeric component compare).
/// Mirrors the Windows UpdateService.
public final class UpdateService: Sendable {   // stateless
    private struct Feed: Decodable {
        let version: String
        let download_url: String?
        let release_notes: String?
    }

    public init() {}

    public var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    public func checkForUpdates() async -> UpdateInfo? {
        guard let url = URL(string: Constants.versionFeedURL) else { return nil }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200,
                  let feed = try? JSONDecoder().decode(Feed.self, from: data) else { return nil }
            guard Self.isNewer(feed.version, than: currentVersion) else { return nil }
            return UpdateInfo(latestVersion: feed.version,
                              downloadURL: feed.download_url ?? Constants.repoURL,
                              releaseNotes: feed.release_notes ?? "")
        } catch {
            Log.debug("Update check failed: \(error)")
            return nil
        }
    }

    /// Compare dotted numeric versions left-to-right. Non-numeric → treated as 0.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        let n = max(a.count, b.count)
        for i in 0..<n {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}

import Foundation

/// Loads/saves AppSettings to settings.json (atomic write). `isFirstRun` reflects
/// the absence of the file, matching the Windows behavior.
public final class SettingsStore {
    public private(set) var settings: AppSettings
    public let isFirstRun: Bool

    private let url = AppPaths.settingsFile
    private let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.outputFormatting = [.prettyPrinted, .sortedKeys]; return e
    }()

    public init() {
        if let data = try? Data(contentsOf: url),
           var loaded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            loaded.fillDefaultsIfNeeded()
            settings = loaded
            isFirstRun = false
        } else {
            var fresh = AppSettings()
            fresh.fillDefaultsIfNeeded()
            settings = fresh
            isFirstRun = true
        }
    }

    public func update(_ mutate: (inout AppSettings) -> Void) {
        mutate(&settings)
        save()
    }

    public func replace(_ newValue: AppSettings) {
        settings = newValue
        save()
    }

    public func save() {
        do {
            let data = try encoder.encode(settings)
            try data.write(to: url, options: .atomic)
        } catch {
            Log.error("Failed to save settings: \(error)")
        }
    }
}

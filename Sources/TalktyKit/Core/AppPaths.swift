import Foundation

/// Canonical on-disk locations. Mirrors the Windows app's %APPDATA%\Talkty layout,
/// mapped to the macOS convention: ~/Library/Application Support/Talkty/.
public enum AppPaths {
    public static let appName = "Talkty"

    public static var supportDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var modelsDir: URL {
        let dir = supportDir.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var logsDir: URL {
        let dir = supportDir.appendingPathComponent("Logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    public static var settingsFile: URL { supportDir.appendingPathComponent("settings.json") }
    public static var historyFile: URL { supportDir.appendingPathComponent("history.json") }
}

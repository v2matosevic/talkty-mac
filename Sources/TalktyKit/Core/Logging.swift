import Foundation
import os

/// Lightweight thread-safe logger: writes a timestamped session file under Logs/
/// and mirrors to the unified log. Replaces the Windows ConcurrentQueue logger.
/// @unchecked: the only mutable state (`handle`) is confined to the serial queue.
public final class Log: @unchecked Sendable {
    public enum Level: String { case debug = "DEBUG", info = "INFO", warning = "WARN", error = "ERROR" }

    public static let shared = Log()

    private let queue = DispatchQueue(label: "hr.version2.talkty.log")
    private let osLog = Logger(subsystem: "hr.version2.talkty", category: "app")
    private var handle: FileHandle?
    private let fileURL: URL

    private init() {
        let stamp = Log.fileStamp(Date())
        fileURL = AppPaths.logsDir.appendingPathComponent("talkty_\(stamp).log")
        // The file sink (session file + latest.log symlink) belongs to the app alone.
        // smoke and TalktyTests link TalktyKit too, and a CLI run must not steal the
        // symlink out from under a live app session or litter stub session files next
        // to real ones (it derailed a real debugging session). Bare executables have
        // no bundle identifier; everyone still mirrors to the unified log.
        guard Bundle.main.bundleIdentifier == "hr.version2.talkty" else { return }
        FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        handle = try? FileHandle(forWritingTo: fileURL)
        // Stable path for live tailing across launches: Logs/latest.log → this session.
        let latest = AppPaths.logsDir.appendingPathComponent("latest.log").path
        try? FileManager.default.removeItem(atPath: latest)
        try? FileManager.default.createSymbolicLink(atPath: latest, withDestinationPath: fileURL.lastPathComponent)
        write(.info, "Talkty started — \(ProcessInfo.processInfo.operatingSystemVersionString), cores=\(ProcessInfo.processInfo.activeProcessorCount)")
    }

    public func write(_ level: Level, _ message: String) {
        let line = "[\(Log.timeStamp(Date()))] [\(level.rawValue)] \(message)\n"
        queue.async { [weak self] in
            self?.handle?.write(Data(line.utf8))
        }
        switch level {
        case .debug: osLog.debug("\(message, privacy: .public)")
        case .info: osLog.info("\(message, privacy: .public)")
        case .warning: osLog.warning("\(message, privacy: .public)")
        case .error: osLog.error("\(message, privacy: .public)")
        }
    }

    /// Flush + close. Call before _exit() at quit.
    public func flush() {
        queue.sync {
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
    }

    public func writeCrash(_ error: Error) {
        let stamp = Log.fileStamp(Date())
        let url = AppPaths.logsDir.appendingPathComponent("crash_\(stamp).log")
        let body = "Talkty crash \(Log.timeStamp(Date()))\n\(type(of: error)): \(error)\n"
        try? body.data(using: .utf8)?.write(to: url)
        write(.error, "CRASH: \(error)")
    }

    /// Collapse whitespace and truncate for a one-line log preview of free text.
    public static func preview(_ s: String, _ max: Int = 120) -> String {
        let flat = s.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > max ? String(flat.prefix(max)) + "…" : flat
    }

    /// Debug lines are gated in release builds — each one otherwise costs string
    /// interpolation, a timestamp format, a queue dispatch, and an os_log call.
    /// Re-enable on an installed app (takes effect at next launch):
    ///   defaults write hr.version2.talkty debugLogging -bool YES
    public static let debugEnabled: Bool = {
        #if DEBUG
        return true
        #else
        return UserDefaults.standard.bool(forKey: "debugLogging")
        #endif
    }()

    // Convenience statics. @autoclosure so a suppressed debug line never even
    // builds its interpolated message.
    public static func debug(_ m: @autoclosure () -> String) {
        guard debugEnabled else { return }
        shared.write(.debug, m())
    }
    public static func info(_ m: String) { shared.write(.info, m) }
    public static func warning(_ m: String) { shared.write(.warning, m) }
    public static func error(_ m: String) { shared.write(.error, m) }

    // Built once — DateFormatter construction is expensive and write() runs on every
    // log line. string(from:) is thread-safe (macOS 10.9+).
    private static let timeFormatter = formatter("HH:mm:ss.SSS")
    private static let fileFormatter = formatter("yyyy-MM-dd_HH-mm-ss")

    private static func formatter(_ fmt: String) -> DateFormatter {
        let f = DateFormatter(); f.dateFormat = fmt; f.locale = Locale(identifier: "en_US_POSIX"); return f
    }
    private static func timeStamp(_ d: Date) -> String { timeFormatter.string(from: d) }
    private static func fileStamp(_ d: Date) -> String { fileFormatter.string(from: d) }
}

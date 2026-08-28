import AppKit

/// NSPasteboard wrapper with the original's retry-on-contention behavior, plus
/// save/restore so auto-paste can leave the user's clipboard intact.
public final class ClipboardService {
    private let pasteboard = NSPasteboard.general

    public init() {}

    @discardableResult
    public func setText(_ text: String, retries: Int = 3) -> Bool {
        for attempt in 0..<retries {
            pasteboard.clearContents()
            if pasteboard.setString(text, forType: .string) { return true }
            if attempt < retries - 1 { Thread.sleep(forTimeInterval: 0.05) }
        }
        Log.warning("Clipboard setText failed after \(retries) attempts")
        return false
    }

    public func getText() -> String? {
        pasteboard.string(forType: .string)
    }

    public var hasText: Bool {
        pasteboard.string(forType: .string) != nil
    }

    /// Snapshot the current string contents (for restore after auto-paste).
    public func snapshot() -> String? { pasteboard.string(forType: .string) }

    public func restore(_ snapshot: String?) {
        guard let snapshot else { return }
        pasteboard.clearContents()
        pasteboard.setString(snapshot, forType: .string)
    }

    /// Copy every item on the pasteboard, all types (text, rich text, images, file
    /// URLs…), into detached items that survive a `clearContents()`. Promised data
    /// that can't be materialized is skipped. Empty array = the clipboard was empty.
    public func snapshotItems() -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            let copy = NSPasteboardItem()
            var any = false
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                    any = true
                }
            }
            return any ? copy : nil
        }
    }

    /// Put a `snapshotItems()` result back. An empty snapshot clears the clipboard,
    /// which is what "restore to empty" means.
    public func restore(items: [NSPasteboardItem]) {
        pasteboard.clearContents()
        if !items.isEmpty { pasteboard.writeObjects(items) }
    }
}

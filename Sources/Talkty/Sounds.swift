import AppKit

/// Subtle, eyes-free audio cues for the dictation lifecycle. Uses the built-in
/// macOS alert sounds so there are no assets to ship. Gated by the soundFeedback
/// setting at the call sites.
enum Sounds {
    static func start()  { play("Tink") }   // listening began
    static func done()   { play("Pop") }    // transcribed / inserted
    static func cancel() { play("Bottle") } // ESC

    private static func play(_ name: String) {
        NSSound(named: name)?.play()
    }
}

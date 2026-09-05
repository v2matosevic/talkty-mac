import Foundation

/// Post-processes Whisper output. Same steps and order as the Windows app (1.3.x):
/// 1. JoinSegments — merge fragments split by pauses, preserve real sentence breaks
/// 2. StripHallucinations — remove Whisper artifacts (non-speech tokens anywhere,
///    YouTube-style closings only at the end of the transcript)
/// 3. ApplyReplacements — case-insensitive, word-boundary vocabulary fixes
/// 4. CleanupPunctuation — false breaks, double periods, spacing, terminal period
///
/// Cleanup runs LAST so the text is normalized after any strip/replace left a gap.
public enum TextPostProcessor {

    // MARK: Compiled patterns (mirror the C# GeneratedRegex set)

    /// Non-speech tokens Whisper emits for background sound or silence. Never real
    /// speech, safe to strip anywhere.
    private static let nonSpeechTokens = try! NSRegularExpression(
        pattern: #"\s*\[(?:MUSIC|BLANK_AUDIO|SILENCE|APPLAUSE)\]\s*|\s*\((?:music|silence|applause|laughing|laughter)\)\s*|\s*♪+\s*"#,
        options: [.caseInsensitive])

    /// End-of-transcript hallucinations: Whisper auto-completes silence with YouTube-style
    /// closings. Stripped ONLY as the trailing content and only as the full phrase. A bare
    /// "Thank you", "Bye" or "subscribe" is kept, people say those. The sentence terminator
    /// before the phrase is captured so the replacement can put it back.
    private static let endOfTranscriptHallucination = try! NSRegularExpression(
        pattern: #"([.!?])?\s+(?:Thank(?:s| you)? for (?:watching|listening)|Please (?:subscribe|like(?:\s+and\s+subscribe)?)|Subscribe to (?:my|the) channel|Don'?t forget to (?:subscribe|like))\.?\s*$|^(?:Thank(?:s| you)? for (?:watching|listening)|Please (?:subscribe|like(?:\s+and\s+subscribe)?)|Subscribe to (?:my|the) channel|Don'?t forget to (?:subscribe|like))\.?\s*$"#,
        options: [.caseInsensitive])

    /// The whole transcript is a lone "you" (Whisper's classic silence hallucination).
    /// Only the entire text qualifies: "I need to call you" is real speech.
    private static let loneYou = try! NSRegularExpression(pattern: #"^\s*you[.!?]?\s*$"#, options: [.caseInsensitive])

    /// A sentence-ending period followed by a lowercase word, a false break from a pause.
    /// The first lookbehind skips the last dot of an ellipsis; the rest keep "e.g. the",
    /// "vs. the old", "etc. and" intact, deleting the dot there corrupts the abbreviation.
    private static let falseSentenceBreak = try! NSRegularExpression(
        pattern: #"(?<!\.)(?<!\be\.g)(?<!\bi\.e)(?<!\betc)(?<!\bvs)(?<!\bcf)(?<!\bapprox)(?<!\bincl)\.(\s+)([a-z])"#)
    /// Leading/trailing ellipsis Whisper adds to continued segments.
    private static let segmentEllipsis = try! NSRegularExpression(pattern: #"^\s*\.{2,}\s*|\s*\.{2,}\s*$"#)
    private static let multipleSpaces = try! NSRegularExpression(pattern: #"  +"#)
    /// Exactly two periods, not part of a "..." ellipsis (both sides guarded).
    private static let doublePeriod = try! NSRegularExpression(pattern: #"(?<!\.)\.{2}(?!\.)"#)

    /// Compiled vocabulary patterns, keyed by the raw replacement key. The patterns
    /// are static for the life of a settings object, recompiling ~40 ICU regexes on
    /// every transcription was pure hot-path waste. NSCache is documented thread-safe;
    /// nonisolated(unsafe) only tells the compiler what Foundation already guarantees.
    nonisolated(unsafe) private static let replacementRegexes = NSCache<NSString, NSRegularExpression>()

    // MARK: Full pipeline

    /// Run the complete post-processing chain.
    public static func process(segments: [String],
                               replacements: [String: String] = [:]) -> String {
        var text = joinSegments(segments)
        text = stripHallucinations(text)
        if !replacements.isEmpty { text = applyReplacements(text, replacements) }
        text = cleanupPunctuation(text)
        return text
    }

    // MARK: Steps

    /// Joins Whisper segments intelligently. Whisper terminates each segment with
    /// punctuation, which creates false breaks when the user paused mid-thought.
    public static func joinSegments(_ segments: [String]) -> String {
        if segments.isEmpty { return "" }
        if segments.count == 1 { return segments[0].trimmingCharacters(in: .whitespacesAndNewlines) }

        var result = ""
        for raw in segments {
            let segment = replace(segmentEllipsis, in: raw, with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if segment.isEmpty { continue }

            if result.isEmpty { result = segment; continue }

            let lastChar = result.last!
            let firstChar = segment.first ?? " "

            if isSentenceEnd(lastChar) && firstChar.isUppercase {
                // Real sentence break: keep it.
                result += " " + segment
            } else if isSentenceEnd(lastChar) && firstChar.isLowercase {
                // False break from a pause: drop the terminal punctuation and merge.
                result.removeLast()
                while result.last == " " { result.removeLast() }
                result += " " + segment
            } else {
                if lastChar != " " { result += " " }
                result += segment
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cleans up punctuation artifacts: merges remaining false breaks, removes double
    /// periods, normalizes spacing, ensures terminal punctuation.
    public static func cleanupPunctuation(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        var result = replace(falseSentenceBreak, in: text, with: " $2")
        result = replace(doublePeriod, in: result, with: ".")
        result = replace(multipleSpaces, in: result, with: " ")
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = result.last, !isSentenceEnd(last), last != "," {
            result += "."
        }
        return result
    }

    /// Applies vocabulary replacements, case-insensitive, word-boundary aware,
    /// preserving capitalization when the matched word was capitalized.
    public static func applyReplacements(_ text: String, _ replacements: [String: String]) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty || replacements.isEmpty { return text }
        var result = text
        for (pattern, replacement) in replacements {
            if pattern.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            let regex: NSRegularExpression
            if let cached = replacementRegexes.object(forKey: pattern as NSString) {
                regex = cached
            } else if let built = try? NSRegularExpression(
                pattern: #"\b"# + NSRegularExpression.escapedPattern(for: pattern) + #"\b"#,
                options: [.caseInsensitive]) {
                replacementRegexes.setObject(built, forKey: pattern as NSString)
                regex = built
            } else { continue }

            // Walk matches back-to-front so ranges stay valid as we substitute.
            let ns = result as NSString
            let matches = regex.matches(in: result, range: NSRange(location: 0, length: ns.length))
            for match in matches.reversed() {
                let matched = ns.substring(with: match.range)
                var sub = replacement
                if let mFirst = matched.first, mFirst.isUppercase,
                   let rFirst = replacement.first, rFirst.isLowercase {
                    sub = rFirst.uppercased() + replacement.dropFirst()
                }
                result = (result as NSString).replacingCharacters(in: match.range, with: sub)
            }
        }
        return result
    }

    /// Strips Whisper hallucinations. Conservative by design:
    /// - non-speech tokens ([MUSIC], ♪, (laughing)) go anywhere;
    /// - YouTube-style closings ("Thanks for watching") only at the end of the transcript;
    /// - a lone "you" transcript (silence) becomes empty;
    /// - bare "Thank you", "Bye", "subscribe", trailing "you" are kept, people say those.
    public static func stripHallucinations(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        var cleaned = replace(nonSpeechTokens, in: text, with: " ")
        cleaned = replace(endOfTranscriptHallucination, in: cleaned, with: "$1")
        cleaned = replace(multipleSpaces, in: cleaned, with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if loneYou.firstMatch(in: cleaned, range: NSRange(location: 0, length: (cleaned as NSString).length)) != nil {
            return ""
        }
        return cleaned
    }

    // MARK: Helpers

    private static func isSentenceEnd(_ c: Character) -> Bool { c == "." || c == "!" || c == "?" }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

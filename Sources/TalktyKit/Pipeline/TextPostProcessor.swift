import Foundation

/// Post-processes Whisper output. Ported 1:1 from the Windows app:
/// 1. JoinSegments — merge fragments split by pauses, preserve real sentence breaks
/// 2. CleanupPunctuation — fix spacing, double periods, trailing artifacts
/// 3. ApplyReplacements — case-insensitive, word-boundary vocabulary fixes (cloud→Claude)
/// 4. StripHallucinations — remove Whisper artifacts at audio boundaries
public enum TextPostProcessor {

    // MARK: Compiled patterns (mirror the C# GeneratedRegex set)

    private static let hallucination = try! NSRegularExpression(
        pattern: #"(?:\s*(?:Thanks? (?:you |for (?:watching|listening))?\.?|Bye\.?|See you\.?|Subscribe\.?|Please (?:subscribe|like)\.?|\[(?:MUSIC|BLANK_AUDIO|SILENCE|APPLAUSE)\]|\((?:music|silence|applause|laughing|laughter)\)|♪+|\.{3,}|you\.?\s*$))"#,
        options: [.caseInsensitive])

    /// A sentence-ending period followed by a lowercase word — a false break from a pause.
    private static let falseSentenceBreak = try! NSRegularExpression(pattern: #"\.(\s+)([a-z])"#)
    /// Leading/trailing ellipsis Whisper adds to continued segments.
    private static let segmentEllipsis = try! NSRegularExpression(pattern: #"^\s*\.{2,}\s*|\s*\.{2,}\s*$"#)
    private static let multipleSpaces = try! NSRegularExpression(pattern: #"  +"#)
    /// Double/triple periods that aren't ellipsis.
    private static let doublePeriod = try! NSRegularExpression(pattern: #"\.{2}(?!\.)"#)

    // MARK: Full pipeline

    /// Run the complete post-processing chain in the original order.
    public static func process(segments: [String],
                               replacements: [String: String] = [:]) -> String {
        var text = joinSegments(segments)
        text = cleanupPunctuation(text)
        if !replacements.isEmpty { text = applyReplacements(text, replacements) }
        text = stripHallucinations(text)
        return text
    }

    // MARK: Steps

    /// Joins Whisper segments intelligently — Whisper terminates each segment with
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
                // Real sentence break — keep it.
                result += " " + segment
            } else if isSentenceEnd(lastChar) && firstChar.isLowercase {
                // False break from a pause — drop the terminal punctuation and merge.
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

    /// Applies vocabulary replacements — case-insensitive, word-boundary aware,
    /// preserving capitalization when the matched word was capitalized.
    public static func applyReplacements(_ text: String, _ replacements: [String: String]) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty || replacements.isEmpty { return text }
        var result = text
        for (pattern, replacement) in replacements {
            if pattern.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            guard let regex = try? NSRegularExpression(
                pattern: #"\b"# + NSRegularExpression.escapedPattern(for: pattern) + #"\b"#,
                options: [.caseInsensitive]) else { continue }

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

    /// Strips common Whisper hallucinations that appear at audio boundaries.
    public static func stripHallucinations(_ text: String) -> String {
        if text.trimmingCharacters(in: .whitespaces).isEmpty { return text }
        return replace(hallucination, in: text, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: Helpers

    private static func isSentenceEnd(_ c: Character) -> Bool { c == "." || c == "!" || c == "?" }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

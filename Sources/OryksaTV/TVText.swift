// ORYKSA TV SDK: how a text is cut for the voice and for the subtitles. License: MIT.
// Lengths are counted in UTF-16 units, as the other ORYKSA SDKs do.
import Foundation

/// `text` with every run of spaces and line breaks as one space, trimmed.
func oryksaTvCollapse(_ text: String) -> String {
    text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

private func oryksaTvLength(_ s: String) -> Int { (s as NSString).length }

private let oryksaTvSentenceEnd = try! NSRegularExpression(pattern: "(?<=[.!?…])\\s+")

/// Splits `text` into pieces of at most `max` characters for the voice, at the end of a sentence
/// when possible, then at a comma, then at a space.
public func oryksaTvSplitForSpeech(_ text: String, max limit: Int) -> [String] {
    let t = oryksaTvCollapse(text)
    if t.isEmpty { return [] }
    if oryksaTvLength(t) <= limit { return [t] }
    var out: [String] = []
    var cur = ""
    for s in oryksaTvSentences(t) {
        for piece in oryksaTvCut(s, limit) {
            if cur.isEmpty {
                cur = piece
            } else if oryksaTvLength(cur) + 1 + oryksaTvLength(piece) <= limit {
                cur += " " + piece
            } else {
                out.append(cur)
                cur = piece
            }
        }
    }
    if !cur.isEmpty { out.append(cur) }
    return out
}

/// The sentences of `text` (ends at `.`, `!`, `?`, `…`, keeping the mark).
public func oryksaTvSentences(_ text: String) -> [String] {
    let t = oryksaTvCollapse(text)
    if t.isEmpty { return [] }
    let ns = t as NSString
    var out: [String] = []
    var start = 0
    for m in oryksaTvSentenceEnd.matches(in: t, range: NSRange(location: 0, length: ns.length)) {
        out.append(ns.substring(with: NSRange(location: start, length: m.range.location - start)))
        start = m.range.location + m.range.length
    }
    out.append(ns.substring(from: start))
    return out.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
}

/// The subtitle lines of `text`: one sentence per line, sentences longer than `max` characters cut
/// at a comma or a space.
public func oryksaTvSubtitleLines(_ text: String, max limit: Int = 90) -> [String] {
    oryksaTvSentences(text).flatMap { oryksaTvCut($0, limit) }
}

/// `s` in pieces of at most `limit` characters, cut at a comma (kept on the first piece) or a space.
func oryksaTvCut(_ s: String, _ limit: Int) -> [String] {
    var rest = s as NSString
    if rest.length <= limit { return [s] }
    var out: [String] = []
    while rest.length > limit {
        let comma = rest.range(of: ", ", options: .backwards,
                               range: NSRange(location: 0, length: min(limit + 2, rest.length))).location
        var at: Int
        if comma != NSNotFound && comma > limit / 3 {
            at = comma + 1 // keep the comma on the first piece
        } else {
            let space = rest.range(of: " ", options: .backwards,
                                   range: NSRange(location: 0, length: min(limit + 1, rest.length))).location
            at = (space == NSNotFound || space <= 0) ? limit : space
        }
        out.append(rest.substring(to: at).trimmingCharacters(in: .whitespacesAndNewlines))
        rest = rest.substring(from: at).trimmingCharacters(in: .whitespacesAndNewlines) as NSString
    }
    if rest.length > 0 { out.append(rest as String) }
    return out
}

/// How long a subtitle stays on screen when there is no voice, in seconds: about 14 characters per
/// second, never under 1.8 s.
public func oryksaTvReadingTime(_ line: String) -> TimeInterval {
    let ms = (Double(oryksaTvLength(line)) / 14 * 1000).rounded()
    return (ms < 1800 ? 1800 : ms) / 1000
}

/// Seconds as nanoseconds for `Task.sleep`.
func oryksaTvNanos(_ seconds: TimeInterval) -> UInt64 {
    seconds <= 0 ? 0 : UInt64(seconds * 1_000_000_000)
}

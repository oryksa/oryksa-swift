// ORYKSA AI Employees SDK. License: MIT. Docs: https://developer.oryksa.com
import Foundation

/// Swear words the customer types show as asterisks (owner rule: every ORYKSA chat). One list for all
/// ORYKSA clients: GET https://app.oryksa.com/widget/profanity.json?lang= (kept 24 hours). The AI's
/// replies already come filtered from the server.
public enum OryksaProfanity {
    private static let urlBase = "https://app.oryksa.com/widget/profanity.json"
    private static let lock = NSLock()
    private static var patterns: [String: NSRegularExpression] = [:]
    private static var loadedAt: [String: Date] = [:]

    /// Language key of the list: pt, br, en or es.
    public static func key(_ lang: String) -> String { lang.contains("br") ? "br" : String(lang.prefix(2)) }

    /// Uses a pattern directly (tests, or your own copy of the list).
    public static func use(_ lang: String, pattern: String, flags: String = "giu") {
        let opts: NSRegularExpression.Options = flags.contains("i") ? [.caseInsensitive] : []
        guard let re = try? NSRegularExpression(pattern: pattern, options: opts) else { return }
        lock.lock(); patterns[key(lang)] = re; loadedAt[key(lang)] = Date(); lock.unlock()
    }

    /// Loads (or refreshes after 24 h) the list for `lang`. Never throws.
    public static func load(_ lang: String, session: URLSession = .shared) async {
        let k = key(lang)
        lock.lock(); let at = loadedAt[k]; lock.unlock()
        if let at = at, Date().timeIntervalSince(at) < 86400 { return }
        guard let url = URL(string: "\(urlBase)?lang=\(k)"),
              let (data, resp) = try? await session.data(from: url),
              (resp as? HTTPURLResponse)?.statusCode == 200,
              let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let pattern = obj["pattern"] as? String else { return }
        use(k, pattern: pattern, flags: (obj["flags"] as? String) ?? "giu")
    }

    /// `text` with the swear words replaced by asterisks (at least 3). Unchanged when the list is not loaded.
    public static func mask(_ text: String, _ lang: String) -> String {
        lock.lock(); let re = patterns[key(lang)]; lock.unlock()
        guard let re = re, !text.isEmpty else { return text }
        let ns = text as NSString
        var out = ""
        var last = 0
        for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let preRange = m.range(at: 1)
            let pre = preRange.location == NSNotFound ? "" : ns.substring(with: preRange)
            let whole = ns.substring(with: m.range)
            let word = String(whole.dropFirst(pre.count)).filter { !$0.isWhitespace }
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += pre + String(repeating: "*", count: max(3, word.count))
            last = m.range.location + m.range.length
        }
        out += ns.substring(from: last)
        return out
    }
}

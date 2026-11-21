// Links in the replies of the AI: text the customer can tap and a card with an Open button. License: MIT.
import Foundation
#if canImport(SwiftUI)
import SwiftUI
#endif

/// What your app does with a link the AI gave (a product, a service, a page). Return true when your
/// app opened it itself (for example its own product screen); return false and the SDK opens it in
/// the browser (or the app that owns the address).
public typealias OryksaLinkHandler = (URL) -> Bool

private let oryksaUrlPattern = try! NSRegularExpression(pattern: #"https?://[^\s<>"'\)\]]+"#, options: [.caseInsensitive])
private let oryksaMailPattern = try! NSRegularExpression(pattern: #"[A-Za-z0-9_.+-]+@[A-Za-z0-9_-]+(\.[A-Za-z0-9_-]+)+"#)

/// The address without the punctuation that ends the sentence (`.,;:!?…`).
func oryksaTrimEnd(_ u: String) -> String {
    u.replacingOccurrences(of: "[.,;:!?…]+$", with: "", options: .regularExpression)
}

/// A URL for an address of a reply (addresses with accents are encoded).
func oryksaURL(_ s: String) -> URL? {
    if let u = URL(string: s), u.scheme != nil { return u }
    var allowed = CharacterSet.urlFragmentAllowed
    allowed.insert(charactersIn: "#%")
    return s.addingPercentEncoding(withAllowedCharacters: allowed).flatMap { URL(string: $0) }
}

/// The distinct web links of `text`, in order (at most `max`).
public func oryksaLinksIn(_ text: String, max: Int = 3) -> [String] {
    var out: [String] = []
    let ns = text as NSString
    for m in oryksaUrlPattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
        let u = oryksaTrimEnd(ns.substring(with: m.range))
        if !out.contains(u) { out.append(u) }
        if out.count >= max { break }
    }
    return out
}

/// `text` without its web links (for the voice screen: the link is on the button).
public func oryksaWithoutLinks(_ text: String) -> String {
    let ns = text as NSString
    var s = oryksaUrlPattern.stringByReplacingMatches(in: text, range: NSRange(location: 0, length: ns.length), withTemplate: "")
    for (pattern, template) in [(#"[ \t]+\n"#, "\n"), (#"\n{3,}"#, "\n\n"), (#"[ \t]{2,}"#, " "),
                                (#"\s+([.,;!?])"#, "$1"), (#"(?m):\s*$"#, "")] {
        s = s.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
    }
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// The parts of `s` that are links: web addresses and e-mails (as `mailto:`), in order.
func oryksaLinkHits(_ s: String) -> [(NSRange, URL)] {
    let ns = s as NSString
    let all = NSRange(location: 0, length: ns.length)
    var hits: [(NSRange, URL)] = []
    for m in oryksaUrlPattern.matches(in: s, range: all) {
        let u = oryksaTrimEnd(ns.substring(with: m.range))
        if let url = oryksaURL(u) { hits.append((NSRange(location: m.range.location, length: (u as NSString).length), url)) }
    }
    for m in oryksaMailPattern.matches(in: s, range: all) {
        if hits.contains(where: { m.range.location < NSMaxRange($0.0) && NSMaxRange(m.range) > $0.0.location }) { continue }
        if let url = URL(string: "mailto:" + ns.substring(with: m.range)) { hits.append((m.range, url)) }
    }
    return hits.sorted { $0.0.location < $1.0.location }
}

#if canImport(SwiftUI)
/// Text of a message with **bold** parts and links (web and e-mail) the customer can tap.
/// Show it with `Text(oryksaRichText(text, linkColor: color))`.
public func oryksaRichText(_ text: String, linkColor: Color? = nil) -> AttributedString {
    var out = AttributedString()
    let parts = text.components(separatedBy: "**")
    if parts.count < 3 {
        oryksaAppendLinks(text, bold: false, linkColor, &out)
        return out
    }
    for (i, p) in parts.enumerated() where !p.isEmpty {
        oryksaAppendLinks(p, bold: i % 2 == 1, linkColor, &out)
    }
    return out
}

private func oryksaAppendLinks(_ s: String, bold: Bool, _ linkColor: Color?, _ out: inout AttributedString) {
    let ns = s as NSString
    func add(_ part: String, _ link: URL?) {
        var a = AttributedString(part)
        if bold { a.inlinePresentationIntent = .stronglyEmphasized }
        if let link = link {
            a.link = link
            a[AttributeScopes.SwiftUIAttributes.UnderlineStyleAttribute.self] = Text.LineStyle.single
            if let c = linkColor { a[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = c }
        }
        out.append(a)
    }
    var at = 0
    for (r, url) in oryksaLinkHits(s) {
        if r.location < at { continue }
        if r.location > at { add(ns.substring(with: NSRange(location: at, length: r.location - at)), nil) }
        add(ns.substring(with: r), url)
        at = NSMaxRange(r)
    }
    if at < ns.length { add(ns.substring(from: at), nil) }
}

/// Sends the taps on the links of a text to `onLink` first (iOS 16 and macOS 13 or later; on
/// older versions the system opens them). The cards call `onLink` on every version.
struct OryksaLinkRouting: ViewModifier {
    let onLink: OryksaLinkHandler?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let h = onLink {
            if #available(iOS 16.0, macOS 13.0, tvOS 16.0, watchOS 9.0, *) {
                content.environment(\.openURL, OpenURLAction { url in h(url) ? .handled : .systemAction })
            } else {
                content
            }
        } else {
            content
        }
    }
}

/// The card under a reply for a link of the business's own site: its picture, its title and an
/// Open button. Links of other sites show the address and the button.
public struct OryksaLinkCard: View {
    let url: String
    let client: OryksaClient
    let openLabel: String
    let onLink: OryksaLinkHandler?
    let onOpened: (() -> Void)?
    let accent: Color
    let ink: Color
    let muted: Color
    let background: Color
    let line: Color
    @State private var preview: OryksaLinkPreview?
    @Environment(\.openURL) private var openURL

    /// - openLabel: text of the button (for example "Abrir").
    /// - onLink: your handler for the links (see `OryksaLinkHandler`).
    /// - onOpened: called when the card opens the link (the voice screen closes itself).
    public init(url: String, client: OryksaClient, openLabel: String, onLink: OryksaLinkHandler? = nil,
                accent: Color = Color(red: 0.357, green: 0.278, blue: 0.878),
                ink: Color = Color(red: 0.122, green: 0.161, blue: 0.216),
                muted: Color = Color(red: 0.42, green: 0.447, blue: 0.502),
                background: Color = .white,
                line: Color = Color(red: 0.898, green: 0.906, blue: 0.922),
                onOpened: (() -> Void)? = nil) {
        self.url = url; self.client = client; self.openLabel = openLabel; self.onLink = onLink
        self.accent = accent; self.ink = ink; self.muted = muted; self.background = background; self.line = line
        self.onOpened = onOpened
    }

    private var host: String {
        let h = URL(string: url)?.host ?? oryksaURL(url)?.host ?? ""
        return h.hasPrefix("www.") ? String(h.dropFirst(4)) : h
    }

    private func open() {
        guard let u = oryksaURL(url) else { return }
        onOpened?()
        if let h = onLink, h(u) { return }
        openURL(u)
    }

    private var placeholder: some View {
        ZStack {
            line
            Image(systemName: "link").font(.system(size: 18, weight: .semibold)).foregroundColor(muted)
        }
    }

    @ViewBuilder
    public var body: some View {
        let p = preview
        let title = (p?.title ?? "").isEmpty ? host : p!.title
        let sub = !(p?.price ?? "").isEmpty ? "\(p!.price) · \(p!.site)" : (!(p?.site ?? "").isEmpty ? p!.site : host)
        let img = p?.image ?? ""
        Button(action: open) {
            HStack(spacing: 10) {
                Group {
                    if img.isEmpty {
                        placeholder
                    } else {
                        AsyncImage(url: URL(string: img)) { phase in
                            if let image = phase.image { image.resizable().scaledToFill() } else { placeholder }
                        }
                    }
                }
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13.5, weight: .bold)).foregroundColor(ink).lineLimit(2)
                        .multilineTextAlignment(.leading)
                    if !sub.isEmpty { Text(sub).font(.system(size: 11.5)).foregroundColor(muted).lineLimit(1) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(openLabel).font(.system(size: 13, weight: .bold)).foregroundColor(.white)
                    .padding(.horizontal, 14).frame(minHeight: 36)
                    .background(Capsule().fill(accent))
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(background))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(openLabel): \(title)")
        .task(id: url) {
            if let got = await client.linkPreview(url) { preview = got }
        }
    }
}
#endif

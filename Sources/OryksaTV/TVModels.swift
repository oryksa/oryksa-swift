// ORYKSA TV SDK for Apple TV: what the TV pieces read from the ORYKSA server. License: MIT.
// The same contract as the Flutter (`package:oryksa/tv.dart`) and Android (`com.oryksa.sdk.tv`) SDKs.
@_exported import Oryksa
import Foundation
import os

let oryksaTvLog = Logger(subsystem: "com.oryksa.sdk", category: "tv")

/// The TV the app runs on, sent as `platform` to ORYKSA (so the owner's reports say "in your app
/// (Apple TV)"). On Apple TV the client sends `tvos` by itself.
public enum OryksaTvPlatform: String, CaseIterable, Sendable {
    /// Android TV and Google TV.
    case androidTv = "android_tv"
    /// Amazon Fire TV with Fire OS.
    case fireTv = "fire_tv"
    /// Amazon Fire TV with Vega OS.
    case vega = "vega"
    /// Samsung (Tizen).
    case tizen = "tizen"
    /// LG (webOS).
    case webos = "webos"
    /// Hisense (VIDAA).
    case vidaa = "vidaa"
    /// Apple TV.
    case tvos = "tvos"
    /// Roku.
    case roku = "roku"

    /// The value sent to the API.
    public var wire: String { rawValue }
}

// MARK: - Locale

/// Normalises a locale string (`pt_BR`, `pt-br`, `PT-BR`) to `pt-BR`. Empty stays empty.
public func oryksaTvNormalizeLocale(_ raw: String) -> String {
    let parts = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        .replacingOccurrences(of: "_", with: "-")
        .split(separator: "-")
        .map(String.init)
        .filter { !$0.isEmpty }
    guard let first = parts.first else { return "" }
    var out = [first.lowercased()]
    for s in parts.dropFirst() {
        if s.count == 4 {
            out.append(s.prefix(1).uppercased() + s.dropFirst().lowercased()) // script, e.g. Latn
        } else {
            out.append(s.uppercased()) // region, e.g. BR or 419
        }
    }
    return out.joined(separator: "-")
}

/// BCP-47 tag of a `Locale` with a hyphen: `pt-BR`, `es-419`, `en`.
public func oryksaTvLocaleTag(_ locale: Locale) -> String {
    let id = locale.identifier.split(separator: "@").first.map(String.init) ?? locale.identifier
    return oryksaTvNormalizeLocale(id)
}

/// The language the person chose for the device (`pt-BR`, `en-US`...).
public func oryksaTvDeviceLocale() -> String {
    oryksaTvNormalizeLocale(Locale.preferredLanguages.first ?? Locale.current.identifier)
}

/// The language code the chat endpoint has always taken (`en`, `pt`, `br`, `es`...):
/// `pt-BR` is `br`, any other Portuguese is `pt`, the rest is the language code.
public func oryksaTvChatLang(_ locale: String) -> String {
    let l = oryksaTvNormalizeLocale(locale)
    if l.isEmpty { return "" }
    let lang = l.split(separator: "-").first.map(String.init) ?? l
    if lang == "pt" { return l == "pt-BR" ? "br" : "pt" }
    return lang
}

// MARK: - JSON helpers

/// A JSON value as text (nil for a missing value or JSON null).
func oryksaTvText(_ v: Any?) -> String? {
    guard let v = v, !(v is NSNull) else { return nil }
    if let s = v as? String { return s }
    if let n = v as? NSNumber { return n.stringValue }
    return "\(v)"
}

/// A JSON string that is not empty once trimmed, or nil.
func oryksaTvNonEmpty(_ v: Any?) -> String? {
    guard let s = v as? String else { return nil }
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    return t.isEmpty ? nil : t
}

/// Characters kept as they are in a query value (everything else is percent-encoded).
private let oryksaTvQueryChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

/// `v` encoded for a query value.
func oryksaTvQuery(_ v: String) -> String {
    v.addingPercentEncoding(withAllowedCharacters: oryksaTvQueryChars) ?? v
}

// MARK: - Configuration (GET /v1/client/agent?locale=, block `tv`)

/// What a button of the assistant panel does (`OryksaTvAction.kind`).
public enum OryksaTvActionKind: String, Sendable {
    /// Sends `OryksaTvAction.message` to the AI.
    case message
    /// Opens the QR to talk on the phone.
    case phoneVoice = "phone_voice"
    /// Closes the panel.
    case close
}

/// A button of the assistant panel, from the ORYKSA server (`tv.actions`).
public struct OryksaTvAction: Equatable, Identifiable, Sendable {
    public let id: String
    public let kind: OryksaTvActionKind
    /// Text on the button.
    public let label: String
    /// For `.message`: what is sent to the AI.
    public let message: String?

    public init(id: String, kind: OryksaTvActionKind, label: String, message: String? = nil) {
        self.id = id; self.kind = kind; self.label = label; self.message = message
    }

    /// Reads one entry of `tv.actions`. Nil when the kind is unknown or the label is empty.
    public static func from(_ j: [String: Any]) -> OryksaTvAction? {
        let label = (oryksaTvText(j["label"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if label.isEmpty { return nil }
        guard let kind = OryksaTvActionKind(rawValue: oryksaTvText(j["kind"]) ?? "") else { return nil }
        let message = oryksaTvText(j["message"])?.trimmingCharacters(in: .whitespacesAndNewlines)
        if kind == .message && (message ?? "").isEmpty { return nil }
        return OryksaTvAction(id: oryksaTvText(j["id"]) ?? label, kind: kind, label: label, message: message)
    }
}

/// Rules of the TV pieces, from the ORYKSA server (`tv.rules`).
public struct OryksaTvRules: Equatable, Sendable {
    /// The phone can be the microphone (QR).
    public let phoneVoice: Bool
    /// `auto`: use the TV microphone when the device has one. `off`: never.
    public let tvMic: String
    /// The assistant panel reads its replies with the presenter's voice.
    public let speakReplies: Bool
    /// Longest text the server speaks in one go: longer texts are split.
    public let presenterMaxChars: Int

    public init(phoneVoice: Bool = true, tvMic: String = "auto", speakReplies: Bool = true, presenterMaxChars: Int = 600) {
        self.phoneVoice = phoneVoice; self.tvMic = tvMic; self.speakReplies = speakReplies
        self.presenterMaxChars = presenterMaxChars
    }

    /// Reads `tv.rules`.
    public static func from(_ j: [String: Any]) -> OryksaTvRules {
        let m = (j["presenter_max_chars"] as? NSNumber)?.intValue
        let maxChars: Int
        if let m = m, m >= 40 { maxChars = m } else { maxChars = 600 }
        return OryksaTvRules(phoneVoice: (j["phone_voice"] as? Bool) != false,
                             tvMic: oryksaTvText(j["tv_mic"]) == "off" ? "off" : "auto",
                             speakReplies: (j["speak_replies"] as? Bool) != false,
                             presenterMaxChars: maxChars)
    }
}

/// The texts of the TV pieces, from the ORYKSA server (`tv.texts`), already in the locale the server
/// chose. A missing key uses a short English text and is logged once.
public struct OryksaTvTexts: Equatable, Sendable {
    /// Short English texts used only when the server does not send a key (older servers).
    public static let fallback: [String: String] = [
        "assistant_title": "Ask the AI",
        "assistant_hint": "Pick a question or talk on your phone",
        "you": "You",
        "thinking": "Thinking…",
        "pair_title": "Talk on your phone",
        "pair_step_scan": "Point your phone camera at the code",
        "pair_step_code": "Or open {url} and type {code}",
        "pair_waiting": "Waiting for the phone…",
        "pair_connected": "Phone connected",
        "pair_expired": "The code expired",
        "listening": "Listening…",
        "phone_left": "The phone disconnected",
        "open_on_phone": "Open on your phone",
        "retry": "Try again",
        "close": "Close",
        "error": "Something went wrong. Try again.",
        "type_message": "Type a message",
        "send": "Send",
    ]

    private static let warnedLock = NSLock()
    private static var warned = Set<String>()

    /// Texts by key.
    public let values: [String: String]

    public init(_ values: [String: String] = [:]) { self.values = values }

    /// The text for `key`, with `{name}` placeholders replaced by `vars`.
    public func get(_ key: String, _ vars: [String: String] = [:]) -> String {
        var s = values[key] ?? ""
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            OryksaTvTexts.warnedLock.lock()
            let first = OryksaTvTexts.warned.insert(key).inserted
            OryksaTvTexts.warnedLock.unlock()
            if first { oryksaTvLog.info("ORYKSA TV: the server sent no text for \(key, privacy: .public); using the English fallback.") }
            s = OryksaTvTexts.fallback[key] ?? key
        }
        for (k, v) in vars { s = s.replacingOccurrences(of: "{\(k)}", with: v) }
        return s
    }
}

/// Everything the TV pieces read from the server: `GET /v1/client/agent?locale=...`, block `tv`.
public struct OryksaTvConfig: Sendable {
    /// Default photo of the AI when the server sends none.
    public static let defaultAvatar = "https://oryksa.com/assets/img/avatar_official_oryksa.png"

    /// The locale the server chose (one of the supported ones), for example `pt-BR`.
    public let locale: String
    /// Changes when the business changes the voice of this locale (keys the voice cache).
    public let voiceRev: String?
    /// Name of the presenter (the AI), for example `ORYKSA`.
    public let presenterName: String
    /// Photo of the presenter.
    public let presenterAvatar: String
    /// Texts of the TV pieces.
    public let texts: OryksaTvTexts
    /// Suggested questions for the assistant panel.
    public let suggestions: [String]
    /// Buttons of the assistant panel.
    public let actions: [OryksaTvAction]
    /// Rules.
    public let rules: OryksaTvRules
    /// False when the server sent no `tv` block (older servers).
    public let fromServer: Bool

    public init(locale: String, voiceRev: String? = nil, presenterName: String = "ORYKSA",
                presenterAvatar: String = OryksaTvConfig.defaultAvatar, texts: OryksaTvTexts = OryksaTvTexts(),
                suggestions: [String] = [], actions: [OryksaTvAction] = [], rules: OryksaTvRules = OryksaTvRules(),
                fromServer: Bool = true) {
        self.locale = locale; self.voiceRev = voiceRev; self.presenterName = presenterName
        self.presenterAvatar = presenterAvatar; self.texts = texts; self.suggestions = suggestions
        self.actions = actions; self.rules = rules; self.fromServer = fromServer
    }

    /// Reads the answer of `GET /v1/client/agent?locale=...`. Without a `tv` block (older servers)
    /// `fromServer` is false and the texts are the English fallback.
    public static func fromAgentJSON(_ j: [String: Any], requestedLocale: String) -> OryksaTvConfig {
        let tv = j["tv"] as? [String: Any]
        let t = tv ?? [:]
        let presenter = (t["presenter"] as? [String: Any]) ?? [:]
        var texts: [String: String] = [:]
        for (k, v) in (t["texts"] as? [String: Any]) ?? [:] { texts[k] = oryksaTvText(v) ?? "" }
        let suggestions = ((t["suggestions"] as? [Any]) ?? [])
            .compactMap { oryksaTvText($0)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let actions = ((t["actions"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).flatMap(OryksaTvAction.from) }
        if tv == nil { oryksaTvLog.info("ORYKSA TV: the server sent no \"tv\" block in /client/agent; using the English fallback.") }
        return OryksaTvConfig(
            locale: oryksaTvNonEmpty(t["locale"]) ?? oryksaTvNormalizeLocale(requestedLocale),
            voiceRev: oryksaTvNonEmpty(t["voice_rev"]),
            presenterName: oryksaTvNonEmpty(presenter["name"]) ?? oryksaTvNonEmpty(j["name"]) ?? "ORYKSA",
            presenterAvatar: oryksaTvNonEmpty(presenter["avatar"]) ?? oryksaTvNonEmpty(j["avatar"]) ?? defaultAvatar,
            texts: OryksaTvTexts(texts),
            suggestions: suggestions,
            actions: actions,
            rules: OryksaTvRules.from((t["rules"] as? [String: Any]) ?? [:]),
            fromServer: tv != nil)
    }
}

// MARK: - Presenter voice (POST /v1/client/tts)

/// The presenter's voice for one text (`OryksaTvBackend.speak`).
public struct OryksaTvSpeech: Sendable {
    /// MP3 bytes. Empty when the server only counted the line: subtitles only, or a line the device
    /// already has.
    public let data: Data
    /// Locale the server spoke in (`X-ORYKSA-Locale`).
    public let locale: String
    /// Voice revision (`X-ORYKSA-Voice-Rev`).
    public let voiceRev: String?
    /// Interactions this line used (`X-ORYKSA-Interactions-Spent`), by the ORYKSA interaction cost
    /// table. A line with no number, or less than one, is not shown.
    public let interactionsSpent: Int?
    /// HTTP status of the answer (200 with a new voice, 204 without one); 0 when it did not come from
    /// HTTP (the simulated backend).
    public let status: Int
    /// `X-ORYKSA-Voice-Status` of a 204: `cached`, `captions` or `unavailable`.
    public let voiceStatus: String?

    public init(_ data: Data, locale: String, voiceRev: String? = nil, interactionsSpent: Int? = nil,
                status: Int = 0, voiceStatus: String? = nil) {
        self.data = data; self.locale = locale; self.voiceRev = voiceRev
        self.interactionsSpent = interactionsSpent; self.status = status; self.voiceStatus = voiceStatus
    }
}

// MARK: - Phone pairing (POST /v1/client/tv/pair and its events)

/// A phone pairing (`OryksaTvBackend.pair`): the QR and the code shown on the TV.
public struct OryksaPairing: Equatable, Sendable {
    /// Id of the pairing.
    public let pairId: String
    /// Short code the person can type on the phone.
    public let code: String
    /// What the QR opens.
    public let url: String
    /// Short address shown under the QR.
    public let shortUrl: String
    /// PNG of the QR (empty: the TV shows the code only).
    public let qrPngUrl: String
    /// Seconds to pair before the code expires.
    public let expiresIn: TimeInterval
    /// When the pairing was created on this device.
    public let createdAt: Date

    /// When the code expires.
    public var expiresAt: Date { createdAt.addingTimeInterval(expiresIn) }

    public init(pairId: String, code: String, url: String, shortUrl: String, qrPngUrl: String,
                expiresIn: TimeInterval, createdAt: Date = Date()) {
        self.pairId = pairId; self.code = code; self.url = url; self.shortUrl = shortUrl
        self.qrPngUrl = qrPngUrl; self.expiresIn = expiresIn; self.createdAt = createdAt
    }

    /// Reads the answer of `POST /v1/client/tv/pair`. Throws when it has no `pair_id` or `code`.
    public static func from(_ j: [String: Any]) throws -> OryksaPairing {
        let id = oryksaTvText(j["pair_id"]) ?? ""
        let code = oryksaTvText(j["code"]) ?? ""
        if id.isEmpty || code.isEmpty {
            throw OryksaError(status: 0, code: "invalid_pairing", message: "The pairing has no pair_id or code.")
        }
        let url = oryksaTvText(j["url"]) ?? ""
        return OryksaPairing(pairId: id, code: code, url: url,
                             shortUrl: oryksaTvText(j["short_url"]) ?? url,
                             qrPngUrl: oryksaTvText(j["qr_png_url"]) ?? "",
                             expiresIn: Double((j["expires_in"] as? NSNumber)?.intValue ?? 300))
    }
}

/// Kind of `OryksaPhoneEvent`.
public enum OryksaPhoneEventType: String, Sendable {
    /// The phone opened the page with the code.
    case paired
    /// The person is speaking.
    case listening
    /// The person stopped and nothing was heard.
    case stopped
    /// What the person said (`OryksaPhoneEvent.text`).
    case text
    /// The phone closed the page or lost the connection.
    case phoneLeft = "phone_left"
    /// The code expired before pairing.
    case expired
    /// The TV or the server ended the pairing.
    case closed
    /// A type this SDK does not know (newer servers): ignored.
    case unknown
}

/// One event of the phone, from `GET /v1/client/tv/pair/{id}/events`.
public struct OryksaPhoneEvent: Equatable, Sendable {
    /// Order of the event.
    public let seq: Int
    public let type: OryksaPhoneEventType
    /// For `.text`: what the person said.
    public let text: String?
    /// For `.text`: the language heard.
    public let lang: String?
    /// For `.text`: the final text (always true for now).
    public let isFinal: Bool

    public init(seq: Int, type: OryksaPhoneEventType, text: String? = nil, lang: String? = nil, isFinal: Bool = true) {
        self.seq = seq; self.type = type; self.text = text; self.lang = lang; self.isFinal = isFinal
    }

    /// Reads one entry of `events`.
    public static func from(_ j: [String: Any]) -> OryksaPhoneEvent {
        let raw = oryksaTvText(j["type"]) ?? ""
        let type = (raw == "unknown" ? nil : OryksaPhoneEventType(rawValue: raw)) ?? .unknown
        return OryksaPhoneEvent(seq: (j["seq"] as? NSNumber)?.intValue ?? 0, type: type,
                                text: oryksaTvText(j["text"]), lang: oryksaTvText(j["lang"]),
                                isFinal: (j["final"] as? Bool) != false)
    }
}

/// One answer of the events long-poll.
public struct OryksaPhoneEventsPage: Equatable, Sendable {
    /// `waiting`, `paired`, `expired` or `closed`.
    public let state: String
    /// Pass as `after` in the next call.
    public let next: Int
    /// New events, oldest first.
    public let events: [OryksaPhoneEvent]
    /// Whether a phone is connected right now (`phone`), when the server says it.
    public let phoneConnected: Bool?

    public init(state: String, next: Int, events: [OryksaPhoneEvent] = [], phoneConnected: Bool? = nil) {
        self.state = state; self.next = next; self.events = events; self.phoneConnected = phoneConnected
    }

    /// Reads the answer of `GET /v1/client/tv/pair/{id}/events`.
    public static func from(_ j: [String: Any], after: Int = 0) -> OryksaPhoneEventsPage {
        let events = ((j["events"] as? [Any]) ?? []).compactMap { ($0 as? [String: Any]).map(OryksaPhoneEvent.from) }
        var next = (j["next"] as? NSNumber)?.intValue ?? after
        for e in events where e.seq > next { next = e.seq }
        return OryksaPhoneEventsPage(state: oryksaTvText(j["state"]) ?? "waiting", next: next, events: events,
                                     phoneConnected: j["phone"] as? Bool)
    }
}

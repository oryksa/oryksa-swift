// ORYKSA TV SDK: what the TV pieces need from ORYKSA, and the real backend on the ORYKSA API. License: MIT.
import Foundation
import Oryksa

/// What the TV pieces need from ORYKSA. The real one is `OryksaTvClientBackend`; tests and demos use
/// `OryksaTvFakeBackend`. Your app never changes when one is swapped for the other.
@MainActor
public protocol OryksaTvBackend: AnyObject {
    /// The value sent as `platform` (for example `tvos`).
    var platform: String { get }

    /// The TV configuration for `locale` (texts, presenter, rules). The server picks the supported
    /// locale and says which in `OryksaTvConfig.locale`.
    func config(_ locale: String) async throws -> OryksaTvConfig

    /// The presenter's line `text` in `locale`, charged each time by the ORYKSA interaction cost table
    /// (`OryksaTvSpeech.interactionsSpent`; a line not counted is not shown). `voice` false: subtitles
    /// only, no voice wanted. `cachedRev`: the device already has this line with that voice revision, so
    /// the server may only count it and send no voice. The bytes may be empty (subtitles only). Nil when
    /// the server gave nothing for it. Throws on other errors.
    func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech?

    /// Sends a message to the AI and waits for the reply (the assistant panel).
    func chat(_ message: String, locale: String, appContext: OryksaAppContext?, voice: Bool) async throws -> OryksaReply

    /// An AI task of your app (`client.ai`), charged by the ORYKSA interaction cost table.
    func ai(instructions: String?, input: String?, schema: [String: Any]?) async throws -> OryksaAiResult

    /// Starts pairing a phone: the QR and the code to show.
    func pair(_ locale: String) async throws -> OryksaPairing

    /// Waits up to `wait` seconds for phone events newer than `after` (long-poll).
    func phoneEvents(_ pairId: String, after: Int, wait: TimeInterval) async throws -> OryksaPhoneEventsPage

    /// Ends the pairing.
    func unpair(_ pairId: String) async throws
}

@MainActor
public extension OryksaTvBackend {
    /// `speak` with a voice, not whispered, for a line the device does not have.
    func speak(_ text: String, locale: String) async throws -> OryksaTvSpeech? {
        try await speak(text, locale: locale, whisper: false, voice: true, cachedRev: nil)
    }

    /// `phoneEvents` with the usual wait (25 seconds).
    func phoneEvents(_ pairId: String, after: Int = 0) async throws -> OryksaPhoneEventsPage {
        try await phoneEvents(pairId, after: after, wait: 25)
    }
}

/// The real backend: the ORYKSA API through an `OryksaClient` (its session token, its `platform`).
/// Written against the contract in the TV SDK design (section 9), the same one the Flutter and Android
/// TV SDKs use against the live server.
@MainActor
public final class OryksaTvClientBackend: OryksaTvBackend {
    /// The client with the session token.
    public let client: OryksaClient

    /// The backend on `client`. On Apple TV the client sends `platform: tvos` by itself.
    public init(_ client: OryksaClient) { self.client = client }

    public var platform: String { client.platform }

    public func config(_ locale: String) async throws -> OryksaTvConfig {
        let l = oryksaTvNormalizeLocale(locale)
        let j = try await client.requestJSON("GET", "client/agent", query: l.isEmpty ? nil : "locale=" + oryksaTvQuery(l))
        return OryksaTvConfig.fromAgentJSON(j, requestedLocale: l)
    }

    public func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        let l = oryksaTvNormalizeLocale(locale)
        var body: [String: Any] = ["text": text, "purpose": "presenter", "platform": platform]
        if !l.isEmpty { body["locale"] = l }
        if whisper { body["whisper"] = true }
        // Subtitles only: the server counts the line and sends no voice.
        if !voice { body["voice"] = false }
        // The device has this line with this voice: the server counts it and need not make the voice again.
        if voice, let rev = cachedRev, !rev.isEmpty {
            body["cached"] = true
            body["voice_rev"] = rev
        }
        do {
            let a = try await client.requestAudio("client/tts", body: body)
            return OryksaTvSpeech(a.data,
                                  locale: a.header("x-oryksa-locale") ?? l,
                                  voiceRev: a.header("x-oryksa-voice-rev"),
                                  interactionsSpent: a.header("x-oryksa-interactions-spent").flatMap { Int($0) },
                                  status: a.status,
                                  voiceStatus: a.header("x-oryksa-voice-status"))
        } catch let e as OryksaError where e.code == "voice_unavailable" {
            return nil
        }
    }

    public func chat(_ message: String, locale: String, appContext: OryksaAppContext?, voice: Bool) async throws -> OryksaReply {
        let lang = oryksaTvChatLang(locale)
        return try await client.sendAndWaitReply(message, appContext: appContext, voice: voice, lang: lang.isEmpty ? nil : lang)
    }

    public func ai(instructions: String?, input: String?, schema: [String: Any]?) async throws -> OryksaAiResult {
        try await client.ai(instructions: instructions, input: input, schema: schema)
    }

    public func pair(_ locale: String) async throws -> OryksaPairing {
        let l = oryksaTvNormalizeLocale(locale)
        var body: [String: Any] = ["platform": platform]
        if !l.isEmpty { body["locale"] = l }
        return try OryksaPairing.from(try await client.requestJSON("POST", "client/tv/pair", body: body))
    }

    public func phoneEvents(_ pairId: String, after: Int, wait: TimeInterval) async throws -> OryksaPhoneEventsPage {
        // The server holds the request for up to `wait` (at most 30 s): keep it well under the client's
        // time limit too.
        var secs = Int(wait.rounded(.down))
        let limit = Int(client.timeout) - 5
        if secs > limit { secs = limit }
        if secs > 30 { secs = 30 }
        if secs < 1 { secs = 1 }
        let j = try await client.requestJSON("GET", "client/tv/pair/\(pairId)/events", query: "after=\(after)&wait=\(secs)")
        return OryksaPhoneEventsPage.from(j, after: after)
    }

    public func unpair(_ pairId: String) async throws {
        _ = try await client.requestJSON("DELETE", "client/tv/pair/\(pairId)")
    }
}

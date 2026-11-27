// ORYKSA TV SDK: a SIMULATED backend for tests and demos. License: MIT.
import Foundation
import Oryksa

/// The rules and sample data of the simulated backend (usable from any thread).
public enum OryksaTvSimulated {
    /// The locale the real server would choose for `requested` (the same rule as the approved voice
    /// table: 8 locales, the rest English of the USA).
    public static func resolveLocale(_ requested: String) -> String {
        let l = oryksaTvNormalizeLocale(requested)
        let lang = l.split(separator: "-").first.map(String.init) ?? ""
        let region = l.contains("-") ? (l.split(separator: "-").last.map(String.init) ?? "") : ""
        let latam: Set<String> = ["MX", "AR", "CO", "CL", "PE", "VE", "EC", "GT", "CU", "BO", "DO", "HN", "PY", "SV",
                                  "NI", "CR", "PA", "UY", "PR", "419", "US"]
        switch lang {
        case "pt": return region == "BR" ? "pt-BR" : "pt-PT"
        case "es": return latam.contains(region) ? "es-419" : "es-ES"
        case "fr": return "fr-FR"
        case "de": return "de-DE"
        case "en": return region == "GB" ? "en-GB" : "en-US"
        default: return "en-US"
        }
    }

    /// Sample texts (English, and Portuguese of Brazil and of Portugal, never mixed): the real ones come
    /// from the server. Other languages use English, the only fallback language.
    public static let sampleTexts: [String: [String: String]] = {
        var en = OryksaTvTexts.fallback
        en["assistant_title"] = "(simulated) Talk to ORYKSA"
        return [
            "en": en,
            "pt-PT": [
                "assistant_title": "(simulado) Fala com a ORYKSA",
                "assistant_hint": "Escolhe uma pergunta ou fala pelo telemóvel",
                "you": "Tu",
                "thinking": "A pensar…",
                "pair_title": "Fala pelo telemóvel",
                "pair_step_scan": "Aponta a câmara do telemóvel para o código",
                "pair_step_code": "Ou abre {url} e escreve {code}",
                "pair_waiting": "À espera do telemóvel…",
                "pair_connected": "Telemóvel ligado",
                "pair_expired": "O código expirou",
                "listening": "A ouvir…",
                "phone_left": "O telemóvel desligou-se",
                "open_on_phone": "Abre no telemóvel",
                "retry": "Tentar de novo",
                "close": "Fechar",
                "error": "Não deu. Tenta de novo.",
                "type_message": "Escreve uma mensagem",
                "send": "Enviar",
            ],
            "pt-BR": [
                "assistant_title": "(simulado) Fale com a ORYKSA",
                "assistant_hint": "Escolha uma pergunta ou fale pelo celular",
                "you": "Você",
                "thinking": "Pensando…",
                "pair_title": "Fale pelo celular",
                "pair_step_scan": "Aponte a câmera do celular para o código",
                "pair_step_code": "Ou abra {url} e digite {code}",
                "pair_waiting": "Esperando o celular…",
                "pair_connected": "Celular conectado",
                "pair_expired": "O código expirou",
                "listening": "Ouvindo…",
                "phone_left": "O celular desconectou",
                "open_on_phone": "Abra no celular",
                "retry": "Tentar de novo",
                "close": "Fechar",
                "error": "Não deu certo. Tente de novo.",
                "type_message": "Digitar uma mensagem",
                "send": "Enviar",
            ],
        ]
    }()

    /// The sample texts for a supported locale (`resolveLocale`): pt-BR, pt-PT, otherwise English.
    public static func sampleTexts(for locale: String) -> [String: String] {
        sampleTexts[locale] ?? sampleTexts["en"] ?? [:]
    }

    /// Codes of the simulated pairings, in order (the real alphabet: no I, O, 0 or 1).
    public static let codes = ["K7Q2MZ", "H4PRWX", "T9GBNE", "D3VJSL"]

    /// The pair id of the `n`-th simulated pairing (1-based): `tvp_` and 12 hex, as the server.
    public static func pairId(_ n: Int) -> String { "tvp_" + String(0x5e1000000000 + n, radix: 16) }

    /// The voice revision of every simulated voice.
    public static let voiceRev = "sim-1"
}

/// SIMULATED backend, for tests and demos only. It never calls ORYKSA, never charges interactions and
/// its texts are samples: nothing shown with it proves the real server. It follows the live server's
/// behaviour (a new pairing closes the previous one, 410 after the end, every line counted).
///
/// Drive the phone from your test or demo with `phoneConnects()`, `phoneSays(_:)`, `phoneLeaves()`
/// and `expire()`.
@MainActor
public final class OryksaTvFakeBackend: OryksaTvBackend {
    /// What one `speak` asked: the text, whether a voice was wanted, and the voice revision of a line
    /// the device already had.
    public struct SpeakRequest: Equatable {
        public let text: String
        public let voice: Bool
        public let cachedRev: String?
    }

    public let platform: String
    /// Fixed configuration (nil: the sample one for the asked locale).
    public let fixedConfig: OryksaTvConfig?
    /// Simulated time of each answer, in seconds.
    public let delay: TimeInterval
    private let voice: ((_ text: String, _ locale: String) -> Data?)?
    private let chatReply: (String) -> String

    /// Calls to `speak` (each one is charged on the real server).
    public private(set) var speakCalls = 0
    /// Every `speak`, in order.
    public private(set) var speakRequests: [SpeakRequest] = []
    /// Messages sent with `chat`.
    public private(set) var sentMessages: [String] = []
    /// Calls to `ai`.
    public private(set) var aiCalls = 0
    /// Pairings ended with `unpair`.
    public private(set) var unpaired: [String] = []

    private var pairs = 0
    private var pairId: String?
    private var seq = 0
    private var state = "waiting"
    private var phone = false
    private var events: [OryksaPhoneEvent] = []
    private var waiters: [UUID: CheckedContinuation<Void, Never>] = [:]

    /// - voice: the MP3 for a text, or nil for "no voice" (the default: the line is counted and the
    ///   presenter shows the subtitles only).
    /// - chatReply: the reply of the AI to a message.
    public init(platform: String = OryksaTvPlatform.tvos.wire,
                voice: ((_ text: String, _ locale: String) -> Data?)? = nil,
                chatReply: ((String) -> String)? = nil,
                delay: TimeInterval = 0,
                fixedConfig: OryksaTvConfig? = nil) {
        self.platform = platform
        self.voice = voice
        self.chatReply = chatReply ?? { "(simulated) You said: \"\($0)\"" }
        self.delay = delay
        self.fixedConfig = fixedConfig
    }

    /// Same as `OryksaTvSimulated.resolveLocale`.
    nonisolated public static func resolveLocale(_ requested: String) -> String { OryksaTvSimulated.resolveLocale(requested) }

    /// Same as `OryksaTvSimulated.pairId`.
    nonisolated public static func pairIdOf(_ n: Int) -> String { OryksaTvSimulated.pairId(n) }

    private func pause() async {
        if delay > 0 { try? await Task.sleep(nanoseconds: oryksaTvNanos(delay)) }
    }

    public func config(_ locale: String) async throws -> OryksaTvConfig {
        if let c = fixedConfig { return c }
        await pause()
        let l = OryksaTvSimulated.resolveLocale(locale)
        let suggestions: [String]
        let phoneLabel: String
        switch l {
        case "pt-BR": suggestions = ["Como funciona?", "O que você pode fazer?"]; phoneLabel = "Falar pelo celular"
        case "pt-PT": suggestions = ["Como funciona?", "O que podes fazer?"]; phoneLabel = "Falar pelo telemóvel"
        default: suggestions = ["How does it work?", "What can you do?"]; phoneLabel = "Talk on the phone"
        }
        return OryksaTvConfig(locale: l, voiceRev: OryksaTvSimulated.voiceRev, presenterName: "ORYKSA",
                              texts: OryksaTvTexts(OryksaTvSimulated.sampleTexts(for: l)),
                              suggestions: suggestions,
                              actions: [OryksaTvAction(id: "phone_voice", kind: .phoneVoice, label: phoneLabel)])
    }

    public func speak(_ text: String, locale: String, whisper: Bool, voice wanted: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        speakCalls += 1
        speakRequests.append(SpeakRequest(text: text, voice: wanted, cachedRev: cachedRev))
        await pause()
        let l = OryksaTvSimulated.resolveLocale(locale)
        let rev = OryksaTvSimulated.voiceRev
        // As the server: every line is counted (a simulated count here); with no voice wanted, a line the
        // device already has (same revision) or no voice for the locale, it only counts it and sends no voice.
        if !wanted { return OryksaTvSpeech(Data(), locale: l, voiceRev: rev, interactionsSpent: 1, voiceStatus: "captions") }
        if cachedRev == rev { return OryksaTvSpeech(Data(), locale: l, voiceRev: rev, interactionsSpent: 1, voiceStatus: "cached") }
        guard let b = self.voice?(text, l), !b.isEmpty else {
            return OryksaTvSpeech(Data(), locale: l, voiceRev: rev, interactionsSpent: 1, voiceStatus: "unavailable")
        }
        return OryksaTvSpeech(b, locale: l, voiceRev: rev, interactionsSpent: 1)
    }

    public func chat(_ message: String, locale: String, appContext: OryksaAppContext?, voice: Bool) async throws -> OryksaReply {
        sentMessages.append(message)
        await pause()
        let r = chatReply(message)
        return OryksaReply(status: "replied", reply: r, speech: voice ? r : nil)
    }

    public func ai(instructions: String?, input: String?, schema: [String: Any]?) async throws -> OryksaAiResult {
        aiCalls += 1
        await pause()
        return OryksaAiResult(text: "(simulated) \(input ?? instructions ?? "")".trimmingCharacters(in: .whitespaces),
                              interactionsSpent: 1)
    }

    public func pair(_ locale: String) async throws -> OryksaPairing {
        await pause()
        pairs += 1
        // As the server: a new pairing of the same TV closes the previous one.
        let id = OryksaTvSimulated.pairId(pairs)
        pairId = id
        seq = 0
        state = "waiting"
        phone = false
        events.removeAll()
        let code = OryksaTvSimulated.codes[(pairs - 1) % OryksaTvSimulated.codes.count]
        return OryksaPairing(pairId: id, code: code, url: "https://oryksa.com/tv?c=\(code)", shortUrl: "oryksa.com/tv",
                             qrPngUrl: "", expiresIn: 300)
    }

    /// Adds an event to the pairing now; with `onlyFor`, only when that is still the pairing now.
    private func push(_ type: OryksaPhoneEventType, text: String? = nil, newState: String? = nil, onlyFor: String? = nil) {
        if let only = onlyFor, only != pairId { return }
        seq += 1
        events.append(OryksaPhoneEvent(seq: seq, type: type, text: text, lang: text == nil ? nil : "pt-PT"))
        if let s = newState { state = s }
        if type == .paired { phone = true }
        if type == .phoneLeft || type == .closed { phone = false }
        let w = waiters
        waiters.removeAll()
        for c in w.values { c.resume() }
    }

    /// The phone opened the page.
    public func phoneConnects() { push(.paired, newState: "paired") }

    /// The person said `text` on the phone (a `listening` then a `text` event).
    public func phoneSays(_ text: String) {
        push(.listening)
        push(.text, text: text)
    }

    /// The phone closed the page.
    public func phoneLeaves() { push(.phoneLeft) }

    /// The code expired.
    public func expire() { push(.expired, newState: "expired") }

    /// Waits until the next event or `seconds`.
    private func waitForPush(_ seconds: TimeInterval) async {
        let id = UUID()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            waiters[id] = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: oryksaTvNanos(seconds))
                self?.wake(id)
            }
        }
    }

    private func wake(_ id: UUID) {
        if let c = waiters.removeValue(forKey: id) { c.resume() }
    }

    public func phoneEvents(_ id: String, after: Int, wait: TimeInterval) async throws -> OryksaPhoneEventsPage {
        if id != pairId { return OryksaPhoneEventsPage(state: "closed", next: after) }
        let ended = state == "expired" || state == "closed"
        // As the server: once ended, asking past the last event is 410 pair_expired.
        if ended && after >= seq { throw OryksaError(status: 410, code: "pair_expired", message: "The pairing has ended.") }
        if !events.contains(where: { $0.seq > after }) && !ended { await waitForPush(min(wait, 30)) }
        let fresh = events.filter { $0.seq > after }
        return OryksaPhoneEventsPage(state: state, next: fresh.last?.seq ?? after, events: fresh, phoneConnected: phone)
    }

    public func unpair(_ id: String) async throws {
        unpaired.append(id)
        // Only the pairing it names: the unpair of the old pairing in restart() must not close the new one.
        push(.closed, newState: "closed", onlyFor: id)
    }
}

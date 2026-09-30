// ORYKSA AI Employees SDK for iOS and macOS. License: MIT. Docs: https://developer.oryksa.com
import Foundation

/// SDK version sent in the `X-ORYKSA-SDK` header.
public let oryksaSDKVersion = "1.1.1"

/// Error returned by the ORYKSA API. `code` is stable, for example
/// `interaction_limit_reached`, `rate_limited`, `plan_required` or `session_expired`.
public struct OryksaError: Error, CustomStringConvertible {
    public let status: Int
    public let code: String
    public let message: String
    public var description: String { "OryksaError(\(status), \(code)): \(message)" }
}

/// Public look of the AI employee (the same data the ORYKSA website chat shows).
public struct OryksaAgent: Decodable, Equatable {
    public let name: String
    public let avatar: String
    public let business: String?
    public let greeting: [String: String]
    public let subtitle: [String: String]
    public let suggestions: [String: [String]]
    public let voiceReplies: Bool
    public let conversationId: String?
    /// ElevenLabs voice chosen for the AI in ORYKSA (the server speaks with it).
    public let voice: String?
    /// Main language of the AI (`pt`, `en`, `es`...), from ORYKSA.
    public let language: String?
    /// The AI photo from "Your AI" in ORYKSA (never the owner's photo). Same as `avatar`.
    public var photo: String { avatar }

    enum CodingKeys: String, CodingKey {
        case name, avatar, business, greeting, subtitle, suggestions, voice, language
        case voiceReplies = "voice_replies"
        case conversationId = "conversation_id"
    }

    public init(name: String, avatar: String, business: String? = nil, greeting: [String: String] = [:],
                subtitle: [String: String] = [:], suggestions: [String: [String]] = [:],
                voiceReplies: Bool = false, conversationId: String? = nil, voice: String? = nil, language: String? = nil) {
        self.name = name; self.avatar = avatar; self.business = business; self.greeting = greeting
        self.subtitle = subtitle; self.suggestions = suggestions; self.voiceReplies = voiceReplies
        self.conversationId = conversationId; self.voice = voice; self.language = language
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        name = (try? c.decode(String.self, forKey: .name)) ?? "ORYKSA"
        avatar = (try? c.decode(String.self, forKey: .avatar)) ?? "https://oryksa.com/assets/img/avatar_official_oryksa.png"
        business = try? c.decode(String.self, forKey: .business)
        greeting = (try? c.decode([String: String].self, forKey: .greeting)) ?? [:]
        subtitle = (try? c.decode([String: String].self, forKey: .subtitle)) ?? [:]
        suggestions = (try? c.decode([String: [String]].self, forKey: .suggestions)) ?? [:]
        voiceReplies = (try? c.decode(Bool.self, forKey: .voiceReplies)) ?? false
        conversationId = try? c.decode(String.self, forKey: .conversationId)
        voice = try? c.decode(String.self, forKey: .voice)
        language = try? c.decode(String.self, forKey: .language)
    }

    /// Picks the text for `lang` with fallbacks (br uses pt, then en).
    public static func pick<T>(_ m: [String: T], _ lang: String) -> T? {
        m[lang] ?? (lang == "br" ? m["pt"] : nil) ?? m["en"] ?? m.values.first
    }
}

/// One message of the conversation.
public struct OryksaMessage: Decodable, Equatable {
    public let role: String
    public let content: String
}

/// Answer of `send`: `replied` with the text, or `pending` while the AI is still writing.
public struct OryksaReply: Decodable {
    public let status: String
    public let reply: String?
    public let conversationId: String?
    /// With `voice: true`: the short spoken version of `reply` (1-2 sentences, no markdown). The whole reply stays in the chat.
    public let speech: String?
    /// The customer whispered: speak `speech` whispered.
    public let whisper: Bool
    enum CodingKeys: String, CodingKey { case status, reply, speech, whisper; case conversationId = "conversation_id" }

    public init(status: String, reply: String?, conversationId: String? = nil, speech: String? = nil, whisper: Bool = false) {
        self.status = status; self.reply = reply; self.conversationId = conversationId; self.speech = speech; self.whisper = whisper
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        status = (try? c.decode(String.self, forKey: .status)) ?? "replied"
        reply = try? c.decode(String.self, forKey: .reply)
        conversationId = try? c.decode(String.self, forKey: .conversationId)
        speech = try? c.decode(String.self, forKey: .speech)
        whisper = (try? c.decode(Bool.self, forKey: .whisper)) ?? false
    }
}

/// Where the customer is inside your app. Sent with each message so the AI knows the current
/// screen (for example a product page) and answers about it.
public struct OryksaAppContext: Equatable {
    public var screen: String?
    public var title: String?
    public var items: [String]
    public init(screen: String? = nil, title: String? = nil, items: [String] = []) {
        self.screen = screen; self.title = title; self.items = items
    }
    /// JSON sent to the API.
    public var json: [String: Any] {
        var d: [String: Any] = [:]
        if let screen = screen { d["screen"] = screen }
        if let title = title { d["title"] = title }
        if !items.isEmpty { d["items"] = Array(items.prefix(20)) }
        return d
    }
}

/// In-app client. Uses a short-lived session token (`oryk_cs_...`) created by YOUR server with
/// `POST /v1/sessions`. The secret API key never goes into the app. Pass `getToken` so the client
/// can ask your server for a new token when the current one expires.
public final class OryksaClient {
    private var token: String?
    private let getToken: (() async throws -> String)?
    private let base: URL
    private let session: URLSession

    public init(token: String? = nil,
                getToken: (() async throws -> String)? = nil,
                baseURL: URL = URL(string: "https://api.oryksa.com/v1")!,
                session: URLSession = .shared) {
        precondition(token != nil || getToken != nil, "OryksaClient needs a token or getToken.")
        precondition(!(token ?? "").hasPrefix("oryk_live_"), "Never use the secret API key in an app. Use a session token (oryk_cs_...).")
        self.token = token
        self.getToken = getToken
        self.base = baseURL
        self.session = session
    }

    private func currentToken(force: Bool) async throws -> String {
        if (token == nil || force), let g = getToken { token = try await g() }
        guard let t = token, !t.isEmpty else { throw OryksaError(status: 401, code: "no_token", message: "No session token.") }
        return t
    }

    private func raw(_ method: String, _ path: String, _ body: [String: Any]?, force: Bool,
                     upload: (data: Data, filename: String, type: String)? = nil) async throws -> Data {
        var req = URLRequest(url: base.appendingPathComponent(path))
        req.httpMethod = method
        req.timeoutInterval = 60
        req.setValue("Bearer \(try await currentToken(force: force))", forHTTPHeaderField: "Authorization")
        req.setValue("ios/\(oryksaSDKVersion)", forHTTPHeaderField: "X-ORYKSA-SDK")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if let up = upload {
            let boundary = "oryksa-\(UUID().uuidString)"
            req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
            var b = Data()
            b.append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(up.filename)\"\r\nContent-Type: \(up.type)\r\n\r\n".data(using: .utf8)!)
            b.append(up.data)
            b.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
            req.httpBody = b
        }
        let (data, resp) = try await session.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if status >= 400 {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let e = obj?["error"] as? [String: Any]
            throw OryksaError(status: status, code: (e?["code"] as? String) ?? "http_\(status)",
                              message: (e?["message"] as? String) ?? "Request failed with HTTP \(status)")
        }
        return data
    }

    private func request(_ method: String, _ path: String, _ body: [String: Any]? = nil,
                         upload: (data: Data, filename: String, type: String)? = nil) async throws -> Data {
        do {
            return try await raw(method, path, body, force: false, upload: upload)
        } catch let e as OryksaError where (e.code == "session_expired" || e.status == 401) && getToken != nil {
            return try await raw(method, path, body, force: true, upload: upload)
        }
    }

    /// Name, photo, greeting and suggestions of the AI employee.
    public func agent() async throws -> OryksaAgent {
        try JSONDecoder().decode(OryksaAgent.self, from: try await request("GET", "client/agent"))
    }

    /// Sends a message. The status is `pending` when the AI needs a few more seconds.
    /// - appContext: the screen the customer is on inside your app, so the AI answers about it.
    /// - voice: the reply will be heard; it also carries a short `speech`.
    /// - whisper: the customer whispered; the spoken reply is shorter and whispered.
    /// - voiceStats: audio numbers of this voice turn (sent by the voice screen).
    public func send(_ message: String, appContext: OryksaAppContext? = nil, voice: Bool = false,
                     whisper: Bool = false, voiceStats: [String: Any]? = nil) async throws -> OryksaReply {
        var body: [String: Any] = ["message": message]
        if let ctx = appContext { body["app_context"] = ctx.json }
        if voice { body["voice"] = true }
        if whisper { body["whisper"] = true }
        if let st = voiceStats { body["platform"] = "ios"; body["voice_stats"] = st }
        return try JSONDecoder().decode(OryksaReply.self, from: try await request("POST", "client/chat", body))
    }

    /// Like `sendAndWait`, but returns the whole reply (with `speech` when `voice` is on).
    public func sendAndWaitReply(_ message: String, maxWait: TimeInterval = 40, appContext: OryksaAppContext? = nil,
                                 voice: Bool = false, whisper: Bool = false, voiceStats: [String: Any]? = nil) async throws -> OryksaReply {
        let r = try await send(message, appContext: appContext, voice: voice, whisper: whisper, voiceStats: voiceStats)
        if r.status != "pending" { return r }
        let end = Date().addingTimeInterval(maxWait)
        while Date() < end {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            if let last = try await messages().last, last.role == "assistant" {
                return OryksaReply(status: "replied", reply: last.content, conversationId: r.conversationId, whisper: whisper)
            }
        }
        return r
    }

    /// The AI's voice (ElevenLabs, the voice chosen in ORYKSA) for one reply of this conversation, as MP3.
    /// Returns nil when the voice is not available: then show the text only (never a robot voice).
    public func tts(_ text: String, whisper: Bool = false) async -> Data? {
        var body: [String: Any] = ["text": text]
        if whisper { body["whisper"] = true }
        return try? await request("POST", "client/tts", body)
    }

    /// Turns the customer's voice into text. `wav` is 16 kHz mono PCM16 WAV, up to 15 seconds.
    /// Returns "" when nothing was said and nil when it failed.
    public func transcribe(_ wav: Data) async -> String? {
        guard let d = try? await request("POST", "client/transcribe", nil, upload: (wav, "voice.wav", "audio/wav")),
              let obj = (try? JSONSerialization.jsonObject(with: d)) as? [String: Any] else { return nil }
        return ((obj["text"] as? String) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Reports a voice turn that produced no message (nothing heard, a cut with nothing said).
    public func voiceStats(_ stats: [String: Any]) async {
        _ = try? await request("POST", "client/voice-stats", ["platform": "ios", "voice_stats": stats])
    }

    /// Messages of this conversation.
    public func messages() async throws -> [OryksaMessage] {
        struct Wrap: Decodable { let messages: [OryksaMessage]? }
        return (try JSONDecoder().decode(Wrap.self, from: try await request("GET", "client/messages"))).messages ?? []
    }

    /// Sends a message and waits for the reply text.
    public func sendAndWait(_ message: String, maxWait: TimeInterval = 40, appContext: OryksaAppContext? = nil) async throws -> String? {
        try await sendAndWaitReply(message, maxWait: maxWait, appContext: appContext).reply
    }
}

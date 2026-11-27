// ORYKSA AI Employees SDK for iOS, macOS and tvOS. License: MIT. Docs: https://developer.oryksa.com
import Foundation

/// SDK version sent in the `X-ORYKSA-SDK` header. Has to match `s.version` in Oryksa.podspec.
public let oryksaSDKVersion = "1.2.0"

/// Error returned by the ORYKSA API. `code` is stable, for example
/// `interaction_limit_reached`, `rate_limited`, `plan_required` or `session_expired`.
public struct OryksaError: Error, CustomStringConvertible {
    public let status: Int
    public let code: String
    public let message: String
    public var description: String { "OryksaError(\(status), \(code)): \(message)" }

    public init(status: Int, code: String, message: String) {
        self.status = status; self.code = code; self.message = message
    }
}

/// The answer of `OryksaClient.requestAudio`: the bytes (empty on a 204), the HTTP status and the
/// headers (names in lower case).
public struct OryksaAudioResponse {
    public let status: Int
    public let data: Data
    public let headers: [String: String]

    public init(status: Int, data: Data, headers: [String: String]) {
        self.status = status; self.data = data
        var h: [String: String] = [:]
        for (k, v) in headers { h[k.lowercased()] = v }
        self.headers = h
    }

    /// The value of the header `name` (any case), or nil.
    public func header(_ name: String) -> String? {
        let v = headers[name.lowercased()]?.trimmingCharacters(in: .whitespaces)
        return (v ?? "").isEmpty ? nil : v
    }
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
    /// The ORYKSA voice chosen for the AI in ORYKSA (the server speaks with it).
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

/// Title and picture of a link of the business's own site (`OryksaClient.linkPreview`).
public struct OryksaLinkPreview: Decodable, Equatable {
    /// The link.
    public let url: String
    /// Title of the page (empty for other sites).
    public let title: String
    /// Picture of the page (empty when it has none).
    public let image: String
    /// Name of the site.
    public let site: String
    /// Price, when the page says it (shops).
    public let price: String
    enum CodingKeys: String, CodingKey { case url, title, image, site, price }

    public init(url: String, title: String = "", image: String = "", site: String = "", price: String = "") {
        self.url = url; self.title = title; self.image = image; self.site = site; self.price = price
    }

    public init(from d: Decoder) throws {
        let c = try d.container(keyedBy: CodingKeys.self)
        func text(_ k: CodingKeys) -> String {
            if let s = try? c.decode(String.self, forKey: k) { return s }
            if let n = try? c.decode(Double.self, forKey: k) { return n == n.rounded() && abs(n) < 1e15 ? String(Int(n)) : String(n) }
            return ""
        }
        url = text(.url); title = text(.title); image = text(.image); site = text(.site); price = text(.price)
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
    private let tokenLock = NSLock()
    private let getToken: (() async throws -> String)?
    private let base: URL
    private let session: URLSession

    /// The device sent as `platform` with each request: `ios` by default, `tvos` on Apple TV, or the
    /// value you pass (for example a TV value of `OryksaTvPlatform` in `OryksaTV`).
    public let platform: String

    /// Time limit of each request, in seconds.
    public let timeout: TimeInterval

    /// The `platform` of this device when none is given.
    public static var defaultPlatform: String {
        #if os(tvOS)
        return "tvos"
        #else
        return "ios"
        #endif
    }

    public init(token: String? = nil,
                getToken: (() async throws -> String)? = nil,
                baseURL: URL = URL(string: "https://api.oryksa.com/v1")!,
                session: URLSession = .shared,
                platform: String? = nil,
                timeout: TimeInterval = 60) {
        precondition(token != nil || getToken != nil, "OryksaClient needs a token or getToken.")
        precondition(!(token ?? "").hasPrefix("oryk_live_"), "Never use the secret API key in an app. Use a session token (oryk_cs_...).")
        self.token = token
        self.getToken = getToken
        self.base = baseURL
        self.session = session
        let p = (platform ?? "").trimmingCharacters(in: .whitespaces)
        self.platform = p.isEmpty ? OryksaClient.defaultPlatform : p
        self.timeout = timeout
    }

    /// For apps WITHOUT a server of their own (for example a TV app): the client takes its session token
    /// from the business's PUBLIC chat token (ORYKSA > Connectors > Website chat, the same token the
    /// website chat uses). No secret key is involved, and the conversation is kept apart from the ones
    /// your server creates. Pass a random `conversationId` saved on the device to keep the history.
    ///
    /// - platform: sent as `platform` (only when given) and used by the client.
    /// - appId: your bundle id, sent as `app_id` so the business can allow your app when it limits its
    ///   chat. A filter only: the strong protection is a token from your own server (`POST /v1/sessions`).
    public static func `public`(chatToken: String, conversationId: String? = nil, customerName: String? = nil,
                                baseURL: URL = URL(string: "https://api.oryksa.com/v1")!,
                                session: URLSession = .shared, timeout: TimeInterval = 60,
                                platform: String? = nil, appId: String? = nil) -> OryksaClient {
        let conv = conversationId ?? OryksaClient.randomId()
        let url = baseURL.appendingPathComponent("public/sessions")
        let fetch: () async throws -> String = {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.timeoutInterval = timeout
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("application/json", forHTTPHeaderField: "Accept")
            req.setValue("ios/\(oryksaSDKVersion)", forHTTPHeaderField: "X-ORYKSA-SDK")
            var body: [String: Any] = ["widget_token": chatToken, "conversation_id": conv]
            if let n = customerName, !n.isEmpty { body["customer_name"] = n }
            if let p = platform, !p.isEmpty { body["platform"] = p }
            if let a = appId, !a.isEmpty { body["app_id"] = a }
            req.httpBody = try JSONSerialization.data(withJSONObject: body)
            let (data, resp) = try await session.data(for: req)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let obj = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]) ?? [:]
            guard status == 200 || status == 201, let t = obj["client_token"] as? String, !t.isEmpty else {
                let e = obj["error"] as? [String: Any]
                throw OryksaError(status: status, code: (e?["code"] as? String) ?? "public_session_failed",
                                  message: (e?["message"] as? String) ?? "Could not open the chat.")
            }
            return t
        }
        return OryksaClient(getToken: fetch, baseURL: baseURL, session: session, platform: platform, timeout: timeout)
    }

    private static func randomId() -> String {
        String((0..<24).map { _ in "0123456789abcdef".randomElement()! })
    }

    /// The token now (several requests may run at once, for example the TV long-poll and the presenter).
    private func storedToken() -> String? {
        tokenLock.lock(); defer { tokenLock.unlock() }
        return token
    }

    private func store(_ t: String) {
        tokenLock.lock(); defer { tokenLock.unlock() }
        token = t
    }

    private func currentToken(force: Bool) async throws -> String {
        var t = storedToken()
        if (t == nil || force), let g = getToken {
            let fresh = try await g()
            store(fresh)
            t = fresh
        }
        guard let tok = t, !tok.isEmpty else { throw OryksaError(status: 401, code: "no_token", message: "No session token.") }
        return tok
    }

    private func raw(_ method: String, _ path: String, _ body: [String: Any]?, force: Bool,
                     upload: (data: Data, filename: String, type: String)? = nil,
                     query: String? = nil) async throws -> (Data, HTTPURLResponse?) {
        var url = base.appendingPathComponent(path)
        if let q = query, let withQuery = URL(string: url.absoluteString + "?" + q) { url = withQuery }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.timeoutInterval = timeout
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
        let http = resp as? HTTPURLResponse
        let status = http?.statusCode ?? 0
        if status >= 400 {
            let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let e = obj?["error"] as? [String: Any]
            throw OryksaError(status: status, code: (e?["code"] as? String) ?? "http_\(status)",
                              message: (e?["message"] as? String) ?? "Request failed with HTTP \(status)")
        }
        return (data, http)
    }

    /// One call with the session token, renewed once when it expired.
    private func exchange(_ method: String, _ path: String, _ body: [String: Any]?,
                          upload: (data: Data, filename: String, type: String)? = nil,
                          query: String? = nil) async throws -> (Data, HTTPURLResponse?) {
        do {
            return try await raw(method, path, body, force: false, upload: upload, query: query)
        } catch let e as OryksaError where (e.code == "session_expired" || e.status == 401) && getToken != nil {
            return try await raw(method, path, body, force: true, upload: upload, query: query)
        }
    }

    private func request(_ method: String, _ path: String, _ body: [String: Any]? = nil,
                         upload: (data: Data, filename: String, type: String)? = nil, query: String? = nil) async throws -> Data {
        try await exchange(method, path, body, upload: upload, query: query).0
    }

    /// Low-level call to an endpoint of the ORYKSA API with this session token (renewed when it
    /// expires), for endpoints this class does not wrap (`OryksaTV` uses it). `path` has no leading
    /// slash (`client/agent`); `query` is already encoded (`locale=pt-BR`). Returns the JSON object
    /// (empty for an empty answer). Throws `OryksaError` on errors.
    public func requestJSON(_ method: String, _ path: String, body: [String: Any]? = nil,
                            query: String? = nil) async throws -> [String: Any] {
        let d = try await request(method, path, body, query: query)
        if d.isEmpty { return [:] }
        return ((try? JSONSerialization.jsonObject(with: d)) as? [String: Any]) ?? [:]
    }

    /// Like `requestJSON` for a POST that answers with audio: the bytes, the status and the headers.
    /// Throws `OryksaError` on errors (unlike `tts`, which returns nil).
    public func requestAudio(_ path: String, body: [String: Any]) async throws -> OryksaAudioResponse {
        let (data, http) = try await exchange("POST", path, body)
        var headers: [String: String] = [:]
        for (k, v) in http?.allHeaderFields ?? [:] {
            if let name = k as? String { headers[name.lowercased()] = "\(v)" }
        }
        return OryksaAudioResponse(status: http?.statusCode ?? 0, data: data, headers: headers)
    }

    /// Name, photo, greeting and suggestions of the AI employee.
    public func agent() async throws -> OryksaAgent {
        try JSONDecoder().decode(OryksaAgent.self, from: try await request("GET", "client/agent"))
    }

    private var previews: [String: OryksaLinkPreview] = [:]
    private let previewsLock = NSLock()

    private func cachedPreview(_ url: String) -> OryksaLinkPreview? {
        previewsLock.lock(); defer { previewsLock.unlock() }
        return previews[url]
    }

    private func keepPreview(_ url: String, _ p: OryksaLinkPreview) {
        previewsLock.lock(); defer { previewsLock.unlock() }
        if previews.count > 200 { previews.removeAll() }
        previews[url] = p
    }

    /// Characters kept as they are in a query value (everything else is percent-encoded).
    private static let queryValueChars = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// Title and picture of a link the AI gave, for the card under her reply. Only the pages of the
    /// business's own site (its website chat domains) get a title and a picture. Nil when it cannot
    /// be read; never throws. Kept in memory for this client.
    public func linkPreview(_ url: String) async -> OryksaLinkPreview? {
        if let hit = cachedPreview(url) { return hit }
        guard let enc = url.addingPercentEncoding(withAllowedCharacters: OryksaClient.queryValueChars),
              let d = try? await request("GET", "client/link-preview", query: "url=" + enc),
              let p = try? JSONDecoder().decode(OryksaLinkPreview.self, from: d) else { return nil }
        keepPreview(url, p)
        return p
    }

    /// An AI task of your own app, counted as ORYKSA interactions (1 per answer): read a photo,
    /// extract data, classify, translate, write. It never creates a conversation in the business's
    /// inbox and never acts on the account. Your prompt and your JSON Schema live in your app.
    /// - instructions: what the AI must do.
    /// - input: the text to work on.
    /// - images: up to 4 photos (JPEG/PNG/WebP, about 1.5 MB each; resize to 1600 px).
    /// - schema: a JSON Schema; the answer comes back in `json`.
    public func ai(instructions: String? = nil, input: String? = nil, images: [OryksaImage] = [],
                   schema: [String: Any]? = nil, maxTokens: Int? = nil, temperature: Double? = nil) async throws -> OryksaAiResult {
        let body = try OryksaClient.aiBody(instructions: instructions, input: input, images: images, schema: schema,
                                           maxTokens: maxTokens, temperature: temperature, platform: platform)
        return try OryksaClient.aiResult(try await request("POST", "client/ai", body))
    }

    /// The JSON of `POST /v1/client/ai`.
    static func aiBody(instructions: String? = nil, input: String? = nil, images: [OryksaImage] = [],
                       schema: [String: Any]? = nil, maxTokens: Int? = nil, temperature: Double? = nil,
                       platform: String = "ios") throws -> [String: Any] {
        if (instructions ?? "").isEmpty && (input ?? "").isEmpty && images.isEmpty {
            throw OryksaError(status: 400, code: "invalid_request", message: "ai() needs instructions, input or an image.")
        }
        if images.count > 4 {
            throw OryksaError(status: 400, code: "invalid_request", message: "ai() takes at most 4 images.")
        }
        var body: [String: Any] = ["platform": platform]
        if let i = instructions, !i.isEmpty { body["instructions"] = i }
        if let t = input, !t.isEmpty { body["input"] = t }
        if !images.isEmpty { body["images"] = images.map { ["base64": $0.data.base64EncodedString(), "mime": $0.mime] } }
        if let s = schema { body["schema"] = s }
        if let m = maxTokens { body["max_tokens"] = m }
        if let t = temperature { body["temperature"] = t }
        return body
    }

    /// Reads an `ai_result` answer.
    static func aiResult(_ data: Data) throws -> OryksaAiResult {
        let obj = (try JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let use = obj["oryksa"] as? [String: Any] ?? [:]
        return OryksaAiResult(text: (obj["text"] as? String) ?? "",
                              json: obj["json"] as? [String: Any],
                              interactionsSpent: (use["interactions_spent"] as? NSNumber)?.intValue ?? 0,
                              interactionsRemaining: (use["interactions_remaining"] as? NSNumber)?.intValue)
    }

    /// Sends a message. The status is `pending` when the AI needs a few more seconds.
    /// - appContext: the screen the customer is on inside your app, so the AI answers about it.
    /// - voice: the reply will be heard; it also carries a short `speech`.
    /// - whisper: the customer whispered; the spoken reply is shorter and whispered.
    /// - voiceStats: audio numbers of this voice turn (sent by the voice screen).
    /// - image: a photo from the customer, the AI looks at it (up to 2 MB).
    /// - file: a document from the customer (PDF, Word, text, CSV), the AI reads it (up to 8 MB).
    /// - lang: the language of your app screen (`en`, `pt`, `br`, `es`...). The AI uses it when the
    ///   message alone does not show the language (for example "ok").
    public func send(_ message: String, appContext: OryksaAppContext? = nil, voice: Bool = false,
                     whisper: Bool = false, voiceStats: [String: Any]? = nil,
                     image: OryksaImage? = nil, file: OryksaFile? = nil, lang: String? = nil) async throws -> OryksaReply {
        let body = OryksaClient.chatBody(message, appContext: appContext, voice: voice, whisper: whisper,
                                         voiceStats: voiceStats, image: image, file: file, platform: platform, lang: lang)
        return try JSONDecoder().decode(OryksaReply.self, from: try await request("POST", "client/chat", body))
    }

    /// The JSON of `POST /v1/client/chat`. The client sends its `platform` in every chat request (so
    /// the owner's lead notice says which app the customer used).
    static func chatBody(_ message: String, appContext: OryksaAppContext? = nil, voice: Bool = false, whisper: Bool = false,
                         voiceStats: [String: Any]? = nil, image: OryksaImage? = nil, file: OryksaFile? = nil,
                         platform: String? = nil, lang: String? = nil) -> [String: Any] {
        var body: [String: Any] = ["message": message]
        if let p = platform, !p.isEmpty { body["platform"] = p }
        if let l = lang, !l.isEmpty { body["lang"] = l }
        if let ctx = appContext { body["app_context"] = ctx.json }
        if voice { body["voice"] = true }
        if whisper { body["whisper"] = true }
        if let st = voiceStats { body["platform"] = platform ?? "ios"; body["voice_stats"] = st }
        if let img = image { body["image_base64"] = img.data.base64EncodedString(); body["image_mime"] = img.mime }
        if let f = file { body["file_base64"] = f.data.base64EncodedString(); body["file_name"] = f.name; body["file_mime"] = f.mime }
        return body
    }

    /// Like `sendAndWait`, but returns the whole reply (with `speech` when `voice` is on).
    public func sendAndWaitReply(_ message: String, maxWait: TimeInterval = 40, appContext: OryksaAppContext? = nil,
                                 voice: Bool = false, whisper: Bool = false, voiceStats: [String: Any]? = nil,
                                 image: OryksaImage? = nil, file: OryksaFile? = nil, lang: String? = nil) async throws -> OryksaReply {
        let r = try await send(message, appContext: appContext, voice: voice, whisper: whisper, voiceStats: voiceStats,
                               image: image, file: file, lang: lang)
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

    /// The AI's voice (the ORYKSA voice chosen in ORYKSA) for one reply of this conversation, as MP3.
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
        _ = try? await request("POST", "client/voice-stats", ["platform": platform, "voice_stats": stats])
    }

    /// Messages of this conversation.
    public func messages() async throws -> [OryksaMessage] {
        struct Wrap: Decodable { let messages: [OryksaMessage]? }
        return (try JSONDecoder().decode(Wrap.self, from: try await request("GET", "client/messages"))).messages ?? []
    }

    /// Sends a message and waits for the reply text.
    /// - image / file: a photo or a document from the customer (see `send`).
    public func sendAndWait(_ message: String, maxWait: TimeInterval = 40, appContext: OryksaAppContext? = nil,
                            image: OryksaImage? = nil, file: OryksaFile? = nil, lang: String? = nil) async throws -> String? {
        try await sendAndWaitReply(message, maxWait: maxWait, appContext: appContext, image: image, file: file, lang: lang).reply
    }
}

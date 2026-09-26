// ORYKSA AI Employees SDK for iOS and macOS. License: MIT. Docs: https://developer.oryksa.com
import Foundation

/// SDK version sent in the `X-ORYKSA-SDK` header.
public let oryksaSDKVersion = "1.0.0"

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

    enum CodingKeys: String, CodingKey {
        case name, avatar, business, greeting, subtitle, suggestions
        case voiceReplies = "voice_replies"
        case conversationId = "conversation_id"
    }

    public init(name: String, avatar: String, business: String? = nil, greeting: [String: String] = [:],
                subtitle: [String: String] = [:], suggestions: [String: [String]] = [:],
                voiceReplies: Bool = false, conversationId: String? = nil) {
        self.name = name; self.avatar = avatar; self.business = business; self.greeting = greeting
        self.subtitle = subtitle; self.suggestions = suggestions; self.voiceReplies = voiceReplies
        self.conversationId = conversationId
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
    enum CodingKeys: String, CodingKey { case status, reply; case conversationId = "conversation_id" }
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

    private func raw(_ method: String, _ path: String, _ body: [String: Any]?, force: Bool) async throws -> Data {
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

    private func request(_ method: String, _ path: String, _ body: [String: Any]? = nil) async throws -> Data {
        do {
            return try await raw(method, path, body, force: false)
        } catch let e as OryksaError where (e.code == "session_expired" || e.status == 401) && getToken != nil {
            return try await raw(method, path, body, force: true)
        }
    }

    /// Name, photo, greeting and suggestions of the AI employee.
    public func agent() async throws -> OryksaAgent {
        try JSONDecoder().decode(OryksaAgent.self, from: try await request("GET", "client/agent"))
    }

    /// Sends a message. The status is `pending` when the AI needs a few more seconds.
    public func send(_ message: String) async throws -> OryksaReply {
        try JSONDecoder().decode(OryksaReply.self, from: try await request("POST", "client/chat", ["message": message]))
    }

    /// Messages of this conversation.
    public func messages() async throws -> [OryksaMessage] {
        struct Wrap: Decodable { let messages: [OryksaMessage]? }
        return (try JSONDecoder().decode(Wrap.self, from: try await request("GET", "client/messages"))).messages ?? []
    }

    /// Sends a message and waits for the reply text.
    public func sendAndWait(_ message: String, maxWait: TimeInterval = 40) async throws -> String? {
        let r = try await send(message)
        if r.status != "pending" { return r.reply }
        let end = Date().addingTimeInterval(maxWait)
        while Date() < end {
            try await Task.sleep(nanoseconds: 1_500_000_000)
            if let last = try await messages().last, last.role == "assistant" { return last.content }
        }
        return nil
    }
}

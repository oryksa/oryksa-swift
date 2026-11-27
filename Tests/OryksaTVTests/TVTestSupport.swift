// Helpers of the TV tests. Nothing here calls the real ORYKSA server: HTTP is answered by TVStub.
import Combine
import Foundation
import XCTest
@testable import OryksaTV

/// A backend that passes every call to `inner`; the tests override what they change.
@MainActor
class WrapBackend: OryksaTvBackend {
    let inner: OryksaTvFakeBackend
    init(_ inner: OryksaTvFakeBackend) { self.inner = inner }
    var platform: String { inner.platform }
    func config(_ locale: String) async throws -> OryksaTvConfig { try await inner.config(locale) }
    func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        try await inner.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: cachedRev)
    }
    func chat(_ message: String, locale: String, appContext: OryksaAppContext?, voice: Bool) async throws -> OryksaReply {
        try await inner.chat(message, locale: locale, appContext: appContext, voice: voice)
    }
    func ai(instructions: String?, input: String?, schema: [String: Any]?) async throws -> OryksaAiResult {
        try await inner.ai(instructions: instructions, input: input, schema: schema)
    }
    func pair(_ locale: String) async throws -> OryksaPairing { try await inner.pair(locale) }
    func phoneEvents(_ pairId: String, after: Int, wait: TimeInterval) async throws -> OryksaPhoneEventsPage {
        try await inner.phoneEvents(pairId, after: after, wait: wait)
    }
    func unpair(_ pairId: String) async throws { try await inner.unpair(pairId) }
}

/// A voice player that plays nothing: it remembers what it loaded and "plays" for `playFor` seconds.
@MainActor
final class FakePlayer: OryksaTvAudioPlayer {
    let playFor: TimeInterval
    private(set) var loaded: [String] = []
    private(set) var plays = 0
    private(set) var stops = 0
    private var waiting: CheckedContinuation<Void, Never>?
    private var gen = 0

    init(playFor: TimeInterval = 0.06) { self.playFor = playFor }

    func load(file: URL?, data: Data?) async throws -> TimeInterval? {
        loaded.append(file?.path ?? "memory")
        return playFor
    }

    func play() async throws {
        plays += 1
        gen += 1
        let g = gen
        let seconds = playFor
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finish()
            waiting = c
            Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                guard let self = self, self.gen == g else { return }
                self.finish()
            }
        }
    }

    func stop() {
        stops += 1
        gen += 1
        finish()
    }

    private func finish() {
        let w = waiting
        waiting = nil
        w?.resume()
    }
}

/// Answers the requests of the test clients without the network.
final class TVStub: URLProtocol {
    struct Answer {
        var status: Int
        var headers: [String: String] = [:]
        var body = Data()
        var fail: Error?

        static func json(_ s: String, _ status: Int = 200) -> Answer { Answer(status: status, body: Data(s.utf8)) }
        static func audio(_ bytes: [UInt8], headers: [String: String] = [:]) -> Answer {
            var h = headers
            h["Content-Type"] = "audio/mpeg"
            return Answer(status: 200, headers: h, body: Data(bytes))
        }
        static func noContent(_ headers: [String: String] = [:]) -> Answer { Answer(status: 204, headers: headers) }
        static func network() -> Answer { Answer(status: 0, fail: URLError(.notConnectedToInternet)) }
    }

    struct Seen {
        let request: URLRequest
        let body: Data
        var path: String { request.url?.path ?? "" }
        var method: String { request.httpMethod ?? "" }
        var json: [String: Any] { ((try? JSONSerialization.jsonObject(with: body)) as? [String: Any]) ?? [:] }
        func query(_ name: String) -> String? {
            guard let u = request.url else { return nil }
            return URLComponents(url: u, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
        }
        func header(_ name: String) -> String? { request.value(forHTTPHeaderField: name) }
    }

    private static let lock = NSLock()
    private static var handler: ((Seen) -> Answer)?
    private static var log: [Seen] = []

    /// Sets how the requests are answered and forgets the ones seen.
    static func answer(_ h: @escaping (Seen) -> Answer) {
        lock.lock(); handler = h; log = []; lock.unlock()
    }

    /// The requests seen since the last `answer`.
    static var seen: [Seen] {
        lock.lock(); defer { lock.unlock() }
        return log
    }

    /// A session answered by this stub.
    static func session() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [TVStub.self]
        return URLSession(configuration: cfg)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let s = Seen(request: request, body: TVStub.bodyOf(request))
        TVStub.lock.lock()
        TVStub.log.append(s)
        let h = TVStub.handler
        TVStub.lock.unlock()
        let a = h?(s) ?? Answer.json(#"{"error":{"code":"no_stub"}}"#, 500)
        if let e = a.fail {
            client?.urlProtocol(self, didFailWithError: e)
            return
        }
        var headers = a.headers
        if headers["Content-Type"] == nil { headers["Content-Type"] = "application/json; charset=utf-8" }
        let r = HTTPURLResponse(url: request.url!, statusCode: a.status, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        if !a.body.isEmpty { client?.urlProtocol(self, didLoad: a.body) }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// The body of a request (URLSession hands it over as a stream).
    private static func bodyOf(_ r: URLRequest) -> Data {
        if let b = r.httpBody { return b }
        guard let s = r.httpBodyStream else { return Data() }
        var d = Data()
        s.open()
        var buf = [UInt8](repeating: 0, count: 65536)
        while s.hasBytesAvailable {
            let n = s.read(&buf, maxLength: buf.count)
            if n <= 0 { break }
            d.append(buf, count: n)
        }
        s.close()
        return d
    }
}

/// An MP3-looking answer for a text (the fake player never decodes it).
func fakeMp3(_ text: String, _ locale: String) -> Data? { Data([0xFF, 0xFB] + Array(text.utf8.prefix(8))) }

/// A text no earlier run has kept on this machine.
func fresh(_ s: String) -> String { "\(s) \(UUID().uuidString.prefix(8))." }

/// A new empty folder for the kept lines of one test.
func tempCacheDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("oryksa_tv_test_\(UUID().uuidString)", isDirectory: true)
}

/// Waits (on the main actor) until `ok` is true, at most `seconds`.
@MainActor
func until(_ seconds: TimeInterval = 2, _ ok: () -> Bool) async -> Bool {
    let end = Date().addingTimeInterval(seconds)
    while !ok() && Date() < end { try? await Task.sleep(nanoseconds: 5_000_000) }
    return ok()
}

/// True when `task` finishes within `seconds`.
@MainActor
func finishes(_ task: Task<Void, Never>, within seconds: TimeInterval) async -> Bool {
    final class Flag { var done = false }
    let flag = Flag()
    Task { @MainActor in
        await task.value
        flag.done = true
    }
    return await until(seconds) { flag.done }
}

/// Collects the subtitles the presenter shows, in order, without repeats.
@MainActor
final class LineLog {
    private(set) var lines: [String] = []
    private var sub: Any?

    init(_ p: OryksaPresenter) {
        sub = p.$line.sink { [weak self] l in
            guard let self = self, !l.isEmpty, self.lines.last != l else { return }
            self.lines.append(l)
        }
    }
}

/// Collects the errors of the presenter.
@MainActor
final class ErrorLog {
    private(set) var errors: [Error] = []
    init(_ p: OryksaPresenter) { p.onError = { [weak self] e in self?.errors.append(e) } }
    var codes: [String] { errors.map { ($0 as? OryksaError)?.code ?? "\($0)" } }
}

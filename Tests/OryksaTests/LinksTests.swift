import XCTest
#if canImport(SwiftUI)
import SwiftUI
#endif
@testable import Oryksa

// The reply the TugaFreela app showed as plain text on 21/11/2026 (owner: "os links ainda não estão clicáveis").
private let reply = "Sim, encontrei alguns webdesigners para criar sua landing page. Você pode conferir este serviço de "
    + "landing page profissional focada em conversões:\n"
    + "https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes\n"
    + "Se quiser ver mais opções, aqui está a lista: https://tugafreela.pt/servico/explorar/28."

private let first = "https://tugafreela.pt/wharakawa/criar-uma-landing-page-profissional-focada-em-conversoes"
private let second = "https://tugafreela.pt/servico/explorar/28"

/// Answers the requests of the test client without the network.
final class StubURLProtocol: URLProtocol {
    static var status = 200
    static var body = Data()
    static var seen: [URLRequest] = []
    /// The bodies of the requests (URLSession hands them over as a stream).
    static var bodies: [Data] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.seen.append(request)
        if let b = request.httpBody {
            StubURLProtocol.bodies.append(b)
        } else if let s = request.httpBodyStream {
            var d = Data()
            s.open()
            var buf = [UInt8](repeating: 0, count: 65536)
            while s.hasBytesAvailable {
                let n = s.read(&buf, maxLength: buf.count)
                if n <= 0 { break }
                d.append(buf, count: n)
            }
            s.close()
            StubURLProtocol.bodies.append(d)
        }
        let r = HTTPURLResponse(url: request.url!, statusCode: StubURLProtocol.status, httpVersion: "HTTP/1.1",
                                headerFields: ["Content-Type": "application/json; charset=utf-8"])!
        client?.urlProtocol(self, didReceive: r, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: StubURLProtocol.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class LinksTests: XCTestCase {
    func stubClient(status: Int, json: String) -> OryksaClient {
        StubURLProtocol.status = status
        StubURLProtocol.body = json.data(using: .utf8)!
        StubURLProtocol.seen = []
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return OryksaClient(token: "oryk_cs_test", session: URLSession(configuration: cfg))
    }

    func testTheLinksOfAReplyInOrderWithoutTheFinalDot() {
        XCTAssertEqual(oryksaLinksIn(reply), [first, second])
        XCTAssertEqual(oryksaLinksIn("a https://x.pt/a, b https://x.pt/a! c https://y.pt/b; d https://z.pt/c? e https://w.pt/d"),
                       ["https://x.pt/a", "https://y.pt/b", "https://z.pt/c"])
        XCTAssertEqual(oryksaLinksIn("(see https://x.pt/a) or \"https://y.pt/b\"…"), ["https://x.pt/a", "https://y.pt/b"])
        XCTAssertEqual(oryksaLinksIn("no links here, write to info@x.pt"), [])
    }

    func testTheVoiceScreenTextHasNoAddressesAndNoDanglingColon() {
        let t = oryksaWithoutLinks(reply)
        XCTAssertFalse(t.contains("http"))
        XCTAssertFalse(t.contains("conversões:"))
        XCTAssertTrue(t.contains("focada em conversões"))
        XCTAssertFalse(t.hasSuffix(":"))
        XCTAssertEqual(oryksaWithoutLinks("See https://x.pt/a ."), "See.")
    }

    #if canImport(SwiftUI)
    func testTheLinksInTheTextCanBeTappedAndTheBoldStays() {
        let text = oryksaRichText("**Snowboard** at " + first + ". Mail info@tugafreela.pt or " + second + ".", linkColor: .green)
        var links: [(String, URL)] = []
        var bold: [String] = []
        for run in text.runs {
            let part = String(text[run.range].characters)
            if let l = run.link { links.append((part, l)) }
            if run.inlinePresentationIntent == .stronglyEmphasized { bold.append(part) }
        }
        XCTAssertEqual(links.map { $0.0 }, [first, "info@tugafreela.pt", second])
        XCTAssertEqual(links.map { $0.1.absoluteString }, [first, "mailto:info@tugafreela.pt", second])
        XCTAssertEqual(bold, ["Snowboard"])
        XCTAssertEqual(String(text.characters), "Snowboard at " + first + ". Mail info@tugafreela.pt or " + second + ".")
    }

    @MainActor
    func testEveryEntryPointTakesOnLinkAndTheTrailingCloseStillWorks() {
        let client = OryksaClient(token: "oryk_cs_test")
        let handler: OryksaLinkHandler = { _ in true }
        _ = OryksaChatView(client: client, voice: true) {}
        _ = OryksaChatView(client: client, lang: "pt", onLink: handler) {}
        _ = OryksaChatView(client: client, onLink: handler)
        _ = OryksaChatButton(client: client, onLink: handler)
        _ = OryksaLinkCard(url: first, client: client, openLabel: "Abrir", onLink: handler)
    }
    #endif

    func testThePreviewComesFromTheServerOnceAndIsKept() async throws {
        let c = stubClient(status: 200, json: #"{"object":"link_preview","url":"\#(first)","title":"Eu vou criar uma landing page profissional focada em conversões","image":"","site":"tugafreela.pt","price":""}"#)
        let p = await c.linkPreview(first)
        XCTAssertEqual(p?.title, "Eu vou criar uma landing page profissional focada em conversões")
        XCTAssertEqual(p?.site, "tugafreela.pt")
        XCTAssertEqual(StubURLProtocol.seen.count, 1)
        let req = try XCTUnwrap(StubURLProtocol.seen.first)
        let url = try XCTUnwrap(req.url)
        XCTAssertEqual(url.path, "/v1/client/link-preview")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, first)
        XCTAssertEqual(req.value(forHTTPHeaderField: "Authorization"), "Bearer oryk_cs_test")
        let again = await c.linkPreview(first)
        XCTAssertEqual(again, p)
        XCTAssertEqual(StubURLProtocol.seen.count, 1)
    }

    func testTheWholeAddressGoesInTheQuery() async throws {
        let c = stubClient(status: 200, json: #"{"object":"link_preview","url":"x","title":"T"}"#)
        let u = "https://shop.pt/p?id=5&c=a+b#top"
        _ = await c.linkPreview(u)
        let url = try XCTUnwrap(StubURLProtocol.seen.first?.url)
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.count, 1)
        XCTAssertFalse(url.absoluteString.contains("&c="))
        XCTAssertTrue(url.absoluteString.contains("url=https%3A%2F%2Fshop.pt%2Fp%3Fid%3D5%26c%3Da%2Bb%23top"))
    }

    func testAFailedPreviewIsNilAndNeverThrows() async {
        let c = stubClient(status: 500, json: #"{"error":{"code":"boom","message":"no"}}"#)
        let p = await c.linkPreview(first)
        XCTAssertNil(p)
    }
}

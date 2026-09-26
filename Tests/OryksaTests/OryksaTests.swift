import XCTest
@testable import Oryksa

final class OryksaTests: XCTestCase {
    func testAgentDecodingAndLanguageFallbacks() throws {
        let json = """
        {"name":"ORYKSA","avatar":"https://x/a.jpg","greeting":{"en":"Hi","pt":"Olá"},"suggestions":{"en":["Prices?"]},"voice_replies":true}
        """.data(using: .utf8)!
        let a = try JSONDecoder().decode(OryksaAgent.self, from: json)
        XCTAssertEqual(a.name, "ORYKSA")
        XCTAssertTrue(a.voiceReplies)
        XCTAssertEqual(OryksaAgent.pick(a.greeting, "br"), "Olá")
        XCTAssertEqual(OryksaAgent.pick(a.greeting, "es"), "Hi")
        XCTAssertEqual(OryksaAgent.pick(a.suggestions, "pt"), ["Prices?"])
    }

    func testMissingFieldsUseDefaults() throws {
        let a = try JSONDecoder().decode(OryksaAgent.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(a.name, "ORYKSA")
        XCTAssertTrue(a.avatar.hasPrefix("https://"))
    }

    func testReplyDecoding() throws {
        let r = try JSONDecoder().decode(OryksaReply.self, from: #"{"status":"replied","reply":"Yes","conversation_id":"c1"}"#.data(using: .utf8)!)
        XCTAssertEqual(r.reply, "Yes")
        XCTAssertEqual(r.conversationId, "c1")
    }
}

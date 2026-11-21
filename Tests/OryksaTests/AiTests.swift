// Owner 2026-11-21: the SDK lets the developer have the AI do what THEY want in the app,
// counted as ORYKSA interactions.
import XCTest
@testable import Oryksa

final class AiTests: XCTestCase {
    func testBodyCarriesInstructionsPhotosAndSchema() throws {
        let img = OryksaImage(data: Data([1, 2, 3]))
        let b = try OryksaClient.aiBody(instructions: "Read the tyre size. Never invent.", images: [img],
                                        schema: ["type": "object"], maxTokens: 300)
        XCTAssertEqual(b["instructions"] as? String, "Read the tyre size. Never invent.")
        let imgs = b["images"] as? [[String: String]]
        XCTAssertEqual(imgs?.count, 1)
        XCTAssertEqual(imgs?.first?["mime"], "image/jpeg")
        XCTAssertEqual(imgs?.first?["base64"], Data([1, 2, 3]).base64EncodedString())
        XCTAssertNotNil(b["schema"])
        XCTAssertEqual(b["max_tokens"] as? Int, 300)
        XCTAssertNil(b["message"])
    }

    func testEmptyCallAndTooManyPhotosAreRefused() {
        XCTAssertThrowsError(try OryksaClient.aiBody())
        let p = OryksaImage(data: Data([1]))
        XCTAssertThrowsError(try OryksaClient.aiBody(input: "x", images: [p, p, p, p, p]))
    }

    func testResultReadsTextJsonAndInteractions() throws {
        let raw = #"{"object":"ai_result","text":"{\"size\":\"205/55 R16 91V\"}","json":{"size":"205/55 R16 91V"},"oryksa":{"interactions_spent":1,"interactions_remaining":99}}"#
        let r = try OryksaClient.aiResult(Data(raw.utf8))
        XCTAssertEqual(r.json?["size"] as? String, "205/55 R16 91V")
        XCTAssertEqual(r.interactionsSpent, 1)
        XCTAssertEqual(r.interactionsRemaining, 99)
    }

    func testResultWithoutSchemaHasNoJson() throws {
        let r = try OryksaClient.aiResult(Data(#"{"object":"ai_result","text":"Lisboa.","json":null,"oryksa":{"interactions_spent":1}}"#.utf8))
        XCTAssertEqual(r.text, "Lisboa.")
        XCTAssertNil(r.json)
    }
}

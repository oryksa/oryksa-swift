import XCTest
#if canImport(ImageIO)
import CoreGraphics
import ImageIO
#endif
@testable import Oryksa

final class AttachmentsTests: XCTestCase {
    func stubClient() -> OryksaClient {
        StubURLProtocol.status = 200
        StubURLProtocol.body = #"{"status":"replied","reply":"Recebi o documento."}"#.data(using: .utf8)!
        StubURLProtocol.seen = []
        StubURLProtocol.bodies = []
        let cfg = URLSessionConfiguration.ephemeral
        cfg.protocolClasses = [StubURLProtocol.self]
        return OryksaClient(token: "oryk_cs_test", session: URLSession(configuration: cfg))
    }

    func json(_ d: Data) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: d) as? [String: Any])
    }

    func testADocumentGoesAsFileBase64NameAndMime() async throws {
        let c = stubClient()
        let pdf = Data("%PDF-1.4 orcamento".utf8)
        let r = try await c.send("Veja o orçamento", file: OryksaFile(data: pdf, name: "orcamento.pdf", mime: "application/pdf"))
        XCTAssertEqual(r.reply, "Recebi o documento.")
        let req = try XCTUnwrap(StubURLProtocol.seen.first)
        XCTAssertEqual(req.url?.path, "/v1/client/chat")
        XCTAssertEqual(req.httpMethod, "POST")
        let b = try json(try XCTUnwrap(StubURLProtocol.bodies.first))
        XCTAssertEqual(b["message"] as? String, "Veja o orçamento")
        XCTAssertEqual(b["file_base64"] as? String, pdf.base64EncodedString())
        XCTAssertEqual(b["file_name"] as? String, "orcamento.pdf")
        XCTAssertEqual(b["file_mime"] as? String, "application/pdf")
        XCTAssertNil(b["image_base64"])
    }

    func testAPhotoGoesAsImageBase64AndMime() async throws {
        let c = stubClient()
        let jpg = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3])
        _ = try await c.sendAndWait("", image: OryksaImage(data: jpg))
        let b = try json(try XCTUnwrap(StubURLProtocol.bodies.first))
        XCTAssertEqual(b["message"] as? String, "")
        XCTAssertEqual(b["image_base64"] as? String, jpg.base64EncodedString())
        XCTAssertEqual(b["image_mime"] as? String, "image/jpeg")
        XCTAssertNil(b["file_base64"])
    }

    #if canImport(SwiftUI)
    @MainActor
    func testTheAttachmentsFlagOnEveryEntryPoint() {
        let client = OryksaClient(token: "oryk_cs_test")
        _ = OryksaChatView(client: client, attachments: false) {}
        _ = OryksaChatView(client: client, attachments: false, onLink: { _ in true }) {}
        _ = OryksaChatButton(client: client, attachments: false)
    }
    #endif

    func testNoAttachmentNoAttachmentFields() {
        let b = OryksaClient.chatBody("Olá")
        XCTAssertEqual(b.keys.sorted(), ["message"])
    }

    func testTheLimits() {
        XCTAssertEqual(oryksaMaxPhotoBytes, 2 * 1024 * 1024)
        XCTAssertEqual(oryksaMaxFileBytes, 8 * 1024 * 1024)
        XCTAssertEqual(oryksaDocumentAttachment(data: Data(count: oryksaMaxFileBytes + 1), name: "big.pdf"), .tooBig)
        guard case .file(let f) = oryksaDocumentAttachment(data: Data(count: oryksaMaxFileBytes), name: "Contrato.PDF") else {
            return XCTFail("8 MB is still sent")
        }
        XCTAssertEqual(f.mime, "application/pdf")
        XCTAssertEqual(f.name, "Contrato.PDF")
        XCTAssertEqual(oryksaPhotoAttachment(Data(count: oryksaMaxPhotoBytes + 1)), .tooBig)
        XCTAssertEqual(oryksaPhotoAttachment(Data(count: 10)), .image(OryksaImage(data: Data(count: 10), mime: "image/jpeg")))
    }

    func testAPictureFromTheDocumentPicker() {
        // up to 2 MB it goes as a photo (the AI looks at it), larger as a file
        XCTAssertEqual(oryksaDocumentAttachment(data: Data(count: 1000), name: "foto.png"),
                       .image(OryksaImage(data: Data(count: 1000), mime: "image/png")))
        guard case .file(let f) = oryksaDocumentAttachment(data: Data(count: oryksaMaxPhotoBytes + 1), name: "foto.png") else {
            return XCTFail("a large picture goes as a file")
        }
        XCTAssertEqual(f.mime, "image/png")
    }

    func testTheTypesOfDocument() {
        XCTAssertEqual(oryksaMime(forFileName: "a.pdf"), "application/pdf")
        XCTAssertEqual(oryksaMime(forFileName: "a.doc"), "application/msword")
        XCTAssertEqual(oryksaMime(forFileName: "a.docx"), "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
        XCTAssertEqual(oryksaMime(forFileName: "lista.TXT"), "text/plain")
        XCTAssertEqual(oryksaMime(forFileName: "a.csv"), "text/csv")
        XCTAssertEqual(oryksaMime(forFileName: "a.zip"), "application/octet-stream")
        guard case .file(let f) = oryksaDocumentAttachment(data: Data(count: 5), name: "notas", mime: "text/markdown") else {
            return XCTFail("unknown extension keeps the picker type")
        }
        XCTAssertEqual(f.mime, "text/markdown")
    }

    #if canImport(ImageIO)
    /// A PNG of w x h pixels.
    func png(_ w: Int, _ h: Int) throws -> Data {
        let ctx = try XCTUnwrap(CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.setFillColor(CGColor(red: 0.1, green: 0.5, blue: 0.4, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        let img = try XCTUnwrap(ctx.makeImage())
        let out = NSMutableData()
        let dst = try XCTUnwrap(CGImageDestinationCreateWithData(out as CFMutableData, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dst, img, nil)
        XCTAssertTrue(CGImageDestinationFinalize(dst))
        return out as Data
    }

    func size(_ d: Data) throws -> (Int, Int) {
        let src = try XCTUnwrap(CGImageSourceCreateWithData(d as CFData, nil))
        let p = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        return (p[kCGImagePropertyPixelWidth] as? Int ?? 0, p[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }

    func testAPhotoIsMadeSmallerAsJpeg() throws {
        let big = try XCTUnwrap(oryksaJpeg(try png(3200, 2000)))
        XCTAssertEqual(Array(big.prefix(2)), [0xFF, 0xD8], "JPEG")
        let (w, h) = try size(big)
        XCTAssertEqual(w, 1600)
        XCTAssertEqual(h, 1000)
        let small = try XCTUnwrap(oryksaJpeg(png(800, 600)))
        let (sw, sh) = try size(small)
        XCTAssertEqual(sw, 800, "a small photo keeps its size")
        XCTAssertEqual(sh, 600)
        XCTAssertNil(oryksaJpeg(Data("not a picture".utf8)))
    }
    #endif
}

// Attachments in the chat: a photo (the AI looks at it) or a document (the AI reads it). License: MIT.
import Foundation
#if canImport(ImageIO)
import ImageIO
#endif

/// A photo from the customer (JPEG, PNG or WebP, up to 2 MB). The AI looks at it.
public struct OryksaImage: Equatable {
    /// The picture bytes.
    public let data: Data
    /// `image/jpeg`, `image/png` or `image/webp`.
    public let mime: String
    public init(data: Data, mime: String = "image/jpeg") { self.data = data; self.mime = mime }
}

/// A document from the customer (PDF, Word, text or CSV, up to 8 MB). The AI reads it.
public struct OryksaFile: Equatable {
    /// The file bytes.
    public let data: Data
    /// The file name, for example `orcamento.pdf`.
    public let name: String
    /// The type, for example `application/pdf`.
    public let mime: String
    public init(data: Data, name: String, mime: String = "application/octet-stream") {
        self.data = data; self.name = name; self.mime = mime
    }
}

/// The answer of `OryksaClient.ai(...)`: an AI task of your own app, counted as ORYKSA interactions.
public struct OryksaAiResult {
    /// The AI's answer as text (with a schema, the JSON text).
    public let text: String
    /// The answer as an object, when you passed a JSON Schema and the answer follows it.
    public let json: [String: Any]?
    /// ORYKSA interactions this answer used (by the ORYKSA interaction cost table).
    public let interactionsSpent: Int
    /// ORYKSA interactions left in this period, when known.
    public let interactionsRemaining: Int?
    public init(text: String, json: [String: Any]? = nil, interactionsSpent: Int = 0, interactionsRemaining: Int? = nil) {
        self.text = text; self.json = json; self.interactionsSpent = interactionsSpent; self.interactionsRemaining = interactionsRemaining
    }
}

/// The largest photo the chat sends (after it is made smaller): 2 MB.
public let oryksaMaxPhotoBytes = 2 * 1024 * 1024
/// The largest document the chat sends: 8 MB.
public let oryksaMaxFileBytes = 8 * 1024 * 1024

/// The types of document the attach button offers, by extension.
let oryksaDocMime: [String: String] = [
    "pdf": "application/pdf",
    "doc": "application/msword",
    "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "txt": "text/plain",
    "csv": "text/csv",
    "jpg": "image/jpeg",
    "jpeg": "image/jpeg",
    "png": "image/png",
    "webp": "image/webp",
]

/// The type of a file from its name (`application/octet-stream` when it is not a known one).
public func oryksaMime(forFileName name: String) -> String {
    oryksaDocMime[(name as NSString).pathExtension.lowercased()] ?? "application/octet-stream"
}

/// What the chat sends for something the customer attached.
public enum OryksaAttachment: Equatable {
    case image(OryksaImage)
    case file(OryksaFile)
    /// Larger than the limit: nothing is sent and the chat says so.
    case tooBig
}

/// A document the customer picked: pictures up to 2 MB go as a photo (the AI looks at it), the
/// rest as a file up to 8 MB.
public func oryksaDocumentAttachment(data: Data, name: String, mime: String? = nil) -> OryksaAttachment {
    if data.count > oryksaMaxFileBytes { return .tooBig }
    let type = oryksaDocMime[(name as NSString).pathExtension.lowercased()] ?? mime ?? "application/octet-stream"
    if type.hasPrefix("image/") && data.count <= oryksaMaxPhotoBytes { return .image(OryksaImage(data: data, mime: type)) }
    return .file(OryksaFile(data: data, name: name, mime: type))
}

/// A photo ready to send (already made smaller): up to 2 MB.
public func oryksaPhotoAttachment(_ jpeg: Data) -> OryksaAttachment {
    jpeg.count > oryksaMaxPhotoBytes ? .tooBig : .image(OryksaImage(data: jpeg, mime: "image/jpeg"))
}

#if canImport(ImageIO)
/// A picture (JPEG, PNG, HEIC...) as a JPEG of at most `maxSide` pixels on its longest side, at
/// `quality` (0.8 = 80%), turned the right way up. Nil when it cannot be read.
public func oryksaJpeg(_ data: Data, maxSide: Int = 1600, quality: Double = 0.8) -> Data? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxSide,
    ]
    guard let img = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
    let out = NSMutableData()
    guard let dst = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil) else { return nil }
    CGImageDestinationAddImage(dst, img, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
    guard CGImageDestinationFinalize(dst) else { return nil }
    return out as Data
}
#endif

// What the demo writes for the proof: each answer of the server, never the token.
import Foundation
import os
import OryksaTV

/// The proof log: the unified log (subsystem com.oryksa.tvdemo), the console and the file
/// Library/Caches/ORYKSA_TV_DEMO.log of the app. `last` is the last presenter answer (shown on screen
/// only with the launch argument `-oryksaProof YES`, for the UI test).
@MainActor
final class DemoProofLog: ObservableObject {
    static let shared = DemoProofLog()

    @Published private(set) var last = ""
    @Published private(set) var ttsCount = 0
    private let logger = Logger(subsystem: "com.oryksa.tvdemo", category: "proof")

    /// Library/Caches/ORYKSA_TV_DEMO.log (tvOS apps keep files in Caches).
    let file: URL = (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        ?? FileManager.default.temporaryDirectory).appendingPathComponent("ORYKSA_TV_DEMO.log")

    func write(_ line: String) {
        let l = "ORYKSA_TV_DEMO \(ISO8601DateFormatter().string(from: Date())) \(line)"
        logger.log("\(l, privacy: .public)")
        print(l)
        let data = Data((l + "\n").utf8)
        if let h = try? FileHandle(forWritingTo: file) {
            _ = h.seekToEndOfFile()
            h.write(data)
            h.closeFile()
        } else {
            try? data.write(to: file)
        }
    }

    /// One answer of `POST /v1/client/tts`.
    func tts(_ line: String) {
        ttsCount += 1
        last = "tts#\(ttsCount) \(line)"
        write(last)
    }
}

/// A text on one log line, its quotes kept apart from the line's own.
private func oneLine(_ s: String) -> String {
    s.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        .replacingOccurrences(of: "\"", with: "'")
        .trimmingCharacters(in: .whitespaces)
}

/// Writes what the server answered for each call, for the proof. Technical labels live here, never on screen.
@MainActor
final class DemoLoggingBackend: OryksaTvBackend {
    let inner: OryksaTvBackend
    let log: DemoProofLog

    init(_ inner: OryksaTvBackend, log: DemoProofLog) {
        self.inner = inner
        self.log = log
    }

    var platform: String { inner.platform }

    func config(_ locale: String) async throws -> OryksaTvConfig {
        let c = try await inner.config(locale)
        log.write("config requested=\(locale) locale=\(c.locale) from_server=\(c.fromServer) voice_rev=\(c.voiceRev ?? "-") texts=\(c.texts.values.count)")
        return c
    }

    func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        do {
            let s = try await inner.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: cachedRev)
            guard let sp = s else {
                log.tts("requested=\(locale) voice=\(voice) result=no_voice")
                return nil
            }
            var spent = "-"
            if let n = sp.interactionsSpent { spent = String(n) }
            let sent = "requested=\(locale) voice=\(voice) cached_rev=\(cachedRev ?? "-")"
            let got = "status=\(sp.status) voice_status=\(sp.voiceStatus ?? "-") server_locale=\(sp.locale) voice_rev=\(sp.voiceRev ?? "-")"
            let size = "interactions_spent=\(spent) bytes=\(sp.data.count) chars=\(text.count)"
            log.tts("\(sent) \(got) \(size) text=\"\(oneLine(text))\"")
            return sp
        } catch {
            log.tts("requested=\(locale) voice=\(voice) cached_rev=\(cachedRev ?? "-") error=\(error)")
            throw error
        }
    }

    func chat(_ message: String, locale: String, appContext: OryksaAppContext?, voice: Bool) async throws -> OryksaReply {
        do {
            let r = try await inner.chat(message, locale: locale, appContext: appContext, voice: voice)
            log.write("chat locale=\(locale) status=\(r.status) message=\"\(oneLine(message))\" reply_chars=\(r.reply?.count ?? 0) speech_chars=\(r.speech?.count ?? 0)")
            return r
        } catch {
            log.write("chat locale=\(locale) error=\(error)")
            throw error
        }
    }

    func ai(instructions: String?, input: String?, schema: [String: Any]?) async throws -> OryksaAiResult {
        try await inner.ai(instructions: instructions, input: input, schema: schema)
    }

    func pair(_ locale: String) async throws -> OryksaPairing {
        do {
            // The code is on the TV screen anyway; it is short-lived and serves once.
            let p = try await inner.pair(locale)
            log.write("pair ok code=\(p.code) expires_in=\(Int(p.expiresIn))s qr=\(p.qrPngUrl.isEmpty ? "none" : "server")")
            return p
        } catch {
            log.write("pair error=\(error)")
            throw error
        }
    }

    func phoneEvents(_ pairId: String, after: Int, wait: TimeInterval) async throws -> OryksaPhoneEventsPage {
        let page = try await inner.phoneEvents(pairId, after: after, wait: wait)
        for e in page.events {
            let extra = e.type == .text ? " lang=\(e.lang ?? "-") final=\(e.isFinal) text=\"\(oneLine(e.text ?? ""))\"" : ""
            log.write("phone event seq=\(e.seq) type=\(e.type.rawValue)\(extra)")
        }
        return page
    }

    func unpair(_ pairId: String) async throws {
        try await inner.unpair(pairId)
    }
}

/// The voice of the SIMULATED presenter: silence as long as reading the line, so the device keeps it and
/// the second time it is asked with `cached` (as with the real server). Never a robot voice.
enum DemoVoice {
    static func silence(for text: String) -> Data {
        let seconds = max(1.8, Double(text.count) / 14)
        let rate = 8000
        let samples = Int(Double(rate) * seconds)
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append(Data("RIFF".utf8)); u32(UInt32(36 + samples * 2)); h.append(Data("WAVE".utf8))
        h.append(Data("fmt ".utf8)); u32(16); u16(1); u16(1); u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16)
        h.append(Data("data".utf8)); u32(UInt32(samples * 2))
        h.append(Data(count: samples * 2))
        return h
    }
}

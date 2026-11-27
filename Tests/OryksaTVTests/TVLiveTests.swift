// LIVE test against the real ORYKSA server. It USES ORYKSA INTERACTIONS of the account of the token (3 lines,
// charged by the ORYKSA interaction cost table: a spoken line at the voice price, a subtitles-only line at the
// text price), so it is opt-in: without ORYKSA_LIVE=1 it is skipped and `swift test` / `xcodebuild test` (and CI)
// never call the real server. Run it only with the PUBLIC CHAT TOKEN of a TEST account, given by the environment,
// never written in the repository (see TVOS-SIMULADOR.md):
//   ORYKSA_LIVE=1 ORYKSA_TV_TOKEN_FILE=<file with the token> swift test --filter TVLiveTests
//   (tvOS Simulator: the same variables with the prefix TEST_RUNNER_, see TVOS-SIMULADOR.md)
// Optional ORYKSA_PROOF_OUT=<log file>. The token is never printed; the log has statuses, headers and sizes only.
import Foundation
import XCTest
@testable import OryksaTV

/// Records each presenter request and what the server answered, for the proof.
@MainActor
private final class ProofBackend: OryksaTvBackend {
    struct Line {
        let text: String
        let voice: Bool
        let cachedRev: String?
        let speech: OryksaTvSpeech?
        let error: String?
    }

    let inner: OryksaTvClientBackend
    private(set) var lines: [Line] = []
    private(set) var log: [String] = []

    init(_ inner: OryksaTvClientBackend) { self.inner = inner }

    var platform: String { inner.platform }

    func config(_ locale: String) async throws -> OryksaTvConfig {
        let c = try await inner.config(locale)
        log.append("config requested=\(locale) locale=\(c.locale) from_server=\(c.fromServer) voice_rev=\(c.voiceRev ?? "-")")
        return c
    }

    func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        do {
            let s = try await inner.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: cachedRev)
            lines.append(Line(text: text, voice: voice, cachedRev: cachedRev, speech: s, error: nil))
            let at = ISO8601DateFormatter().string(from: Date())
            let status = s?.status ?? 0
            var spent = "-"
            if let n = s?.interactionsSpent { spent = String(n) }
            let voiceStatus = s?.voiceStatus ?? "-"
            let rev = s?.voiceRev ?? "-"
            let serverLocale = s?.locale ?? "-"
            let bytes = s?.data.count ?? 0
            let sent = "voice=\(voice) cached_rev=\(cachedRev ?? "-") text=\"\(text)\""
            log.append("\(at) POST /v1/client/tts status=\(status) spent=\(spent) voice_status=\(voiceStatus) voice_rev=\(rev) locale=\(serverLocale) bytes=\(bytes) | sent \(sent)")
            return s
        } catch {
            lines.append(Line(text: text, voice: voice, cachedRev: cachedRev, speech: nil, error: "\(error)"))
            log.append("POST /v1/client/tts error=\(error)")
            throw error
        }
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

final class TVLiveTests: XCTestCase {
    /// The public chat token of the TEST account: ORYKSA_TV_TOKEN, or the file named by ORYKSA_TV_TOKEN_FILE.
    private func liveToken(_ env: [String: String]) -> String? {
        if let v = env["ORYKSA_TV_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines), !v.isEmpty { return v }
        guard let f = env["ORYKSA_TV_TOKEN_FILE"], !f.isEmpty,
              let t = try? String(contentsOfFile: (f as NSString).expandingTildeInPath, encoding: .utf8) else { return nil }
        let token = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    @MainActor
    func testLiveNewLineThenTheSameLineCachedThenSubtitlesOnlyAllCharged() async throws {
        let env = ProcessInfo.processInfo.environment
        try XCTSkipUnless(env["ORYKSA_LIVE"] == "1", "live test: uses interactions; set ORYKSA_LIVE=1 and the token of a TEST account")
        guard let token = liveToken(env) else {
            XCTFail("ORYKSA_LIVE=1 needs ORYKSA_TV_TOKEN or ORYKSA_TV_TOKEN_FILE (a TEST account).")
            return
        }
        let client = OryksaClient.public(chatToken: token, conversationId: "tvlive\(Int(Date().timeIntervalSince1970 * 1000))",
                                         platform: OryksaTvPlatform.tvos.wire, appId: "com.oryksa.tvdemo")
        let proof = ProofBackend(OryksaTvClientBackend(client))
        let player = FakePlayer(playFor: 0.05)
        let tv = OryksaTv(backend: proof, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 0.05 }
        let errors = ErrorLog(tv.presenter)
        let shown = LineLog(tv.presenter)

        let stamp = ISO8601DateFormatter().string(from: Date()).suffix(9).prefix(8)
        let line = "Prova ao vivo da cobrança do SDK de TV para Apple TV, às \(stamp)."
        let captions = "Só legendas, sem som, às \(stamp)."
        await tv.presenter.say(line) // 1: new
        await tv.presenter.say(line) // 2: the device has it
        await tv.presenter.say(captions, voice: false) // 3: subtitles only
        tv.close()

        var parts: [String] = []
        parts.append("Swift SDK (OryksaTV) contra o servidor real, conta de TESTE, \(ISO8601DateFormatter().string(from: Date()))")
        parts.append(contentsOf: proof.log)
        parts.append("player.loaded=\(player.loaded)")
        parts.append("player.plays=\(player.plays)")
        parts.append("shown=\(shown.lines)")
        parts.append("errors=\(errors.codes)")
        let spentPerLine: [Int] = proof.lines.map { $0.speech?.interactionsSpent ?? 0 }
        parts.append("spent (by the cost table, per line)=\(spentPerLine)")
        let summary = parts.joined(separator: "\n") + "\n"
        let attachment = XCTAttachment(string: summary)
        attachment.name = "tv-live-proof.txt"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let out = env["ORYKSA_PROOF_OUT"], !out.isEmpty {
            try? summary.write(toFile: (out as NSString).expandingTildeInPath, atomically: true, encoding: .utf8)
        }

        let l = proof.lines
        XCTAssertEqual(l.count, 3)
        guard l.count == 3 else { return }
        XCTAssertEqual(l[0].speech?.status, 200, "a new line comes with its voice")
        XCTAssertNil(l[0].cachedRev)
        XCTAssertEqual(l[1].speech?.status, 204, "the line the device has comes without voice")
        XCTAssertEqual(l[1].speech?.voiceStatus, "cached")
        XCTAssertNotNil(l[1].cachedRev, "sent with cached and its voice_rev")
        XCTAssertEqual(l[2].speech?.status, 204)
        XCTAssertEqual(l[2].speech?.voiceStatus, "captions")
        XCTAssertFalse(l[2].voice)
        // Every line is charged; the number is the cost table's, never fixed here.
        for x in l { XCTAssertGreaterThanOrEqual(x.speech?.interactionsSpent ?? 0, 1, x.text) }
        XCTAssertEqual(player.plays, 2)
        XCTAssertEqual(player.loaded.count, 2)
        XCTAssertEqual(player.loaded.first, player.loaded.last, "the kept voice plays the second time")
        XCTAssertTrue(shown.lines.contains(captions))
        XCTAssertTrue(errors.errors.isEmpty, "\(errors.codes)")
    }
}

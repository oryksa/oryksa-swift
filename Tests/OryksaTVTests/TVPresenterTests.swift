// The presenter and its charging contract (port of the Flutter test/tv_presenter_test.dart).
// On the SIMULATED backend this proves the SDK logic (cache, subtitles, charging requests), not the
// ORYKSA server; the "real client" tests prove the HTTP requests and how the answers are read.
import Combine
import Foundation
import XCTest
@testable import OryksaTV

/// A simulated backend whose configuration revision can change, as the server's.
@MainActor
private final class RevBackend: WrapBackend {
    var rev: () -> String
    var reads = 0
    init(voice: ((String, String) -> Data?)?, rev: @escaping () -> String) {
        self.rev = rev
        super.init(OryksaTvFakeBackend(voice: voice))
    }
    override func config(_ locale: String) async throws -> OryksaTvConfig {
        reads += 1
        return OryksaTvConfig(locale: "pt-BR", voiceRev: rev())
    }
}

/// A server that answers the line without counting it (no `X-ORYKSA-Interactions-Spent`), or refuses it
/// because no interactions are left.
@MainActor
private final class NotCounting: WrapBackend {
    let refuse: Bool
    init(voice: ((String, String) -> Data?)?, refuse: Bool = false) {
        self.refuse = refuse
        super.init(OryksaTvFakeBackend(voice: voice))
    }
    override func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        let s = try await super.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: cachedRev)
        if refuse { throw OryksaError(status: 402, code: "interactions_exhausted", message: "No interactions left.") }
        return OryksaTvSpeech(s?.data ?? Data(), locale: s?.locale ?? locale, voiceRev: s?.voiceRev)
    }
}

/// An older server that does not know `cached`: it makes the voice again (and charges it).
@MainActor
private final class NoCachedHint: WrapBackend {
    init(voice: ((String, String) -> Data?)?) { super.init(OryksaTvFakeBackend(voice: voice)) }
    override func speak(_ text: String, locale: String, whisper: Bool, voice: Bool, cachedRev: String?) async throws -> OryksaTvSpeech? {
        try await super.speak(text, locale: locale, whisper: whisper, voice: voice, cachedRev: nil)
    }
}

final class TVPresenterTests: XCTestCase {
    // MARK: on the simulated backend

    @MainActor
    func testSpeaksWithTheVoiceAndTheSameLineAgainIsChargedAgainAndPlaysTheKeptVoice() async {
        let fake = OryksaTvFakeBackend(voice: fakeMp3)
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        var events: [String] = []
        tv.presenter.onStart = { events.append("start") }
        tv.presenter.onEnd = { events.append("end") }
        var phases = Set<OryksaPresenterPhase>()
        let sub = tv.presenter.$phase.sink { _ = phases.insert($0) }

        let line = fresh("Olá! Sou a ORYKSA")
        await tv.presenter.say(line)
        XCTAssertEqual(fake.speakCalls, 1)
        XCTAssertEqual(player.plays, 1)
        XCTAssertNotEqual(player.loaded.first, "memory", "plays from a file")
        XCTAssertTrue(phases.isSuperset(of: [.preparing, .speaking, .idle]))
        XCTAssertEqual(events, ["start", "end"])
        XCTAssertFalse(tv.presenter.isBusy)

        await tv.presenter.say(line)
        XCTAssertEqual(fake.speakCalls, 2, "each time she says it, it is charged (owner, 26/11/2026)")
        XCTAssertEqual(fake.speakRequests.last?.cachedRev, "sim-1", "the server is told the device has it, so it need not make the voice again")
        XCTAssertEqual(player.plays, 2)
        XCTAssertEqual(player.loaded.last, player.loaded.first, "the kept voice plays")
        sub.cancel()
    }

    @MainActor
    func testAServerThatDoesNotKnowCachedSendsTheVoiceAgainWhichPlays() async {
        let fake = NoCachedHint(voice: fakeMp3)
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        let line = fresh("Olá de novo")
        await tv.presenter.say(line)
        await tv.presenter.say(line)
        XCTAssertEqual(fake.inner.speakCalls, 2)
        XCTAssertEqual(player.plays, 2)
    }

    @MainActor
    func testAServerWithoutVoiceRevInTheConfigurationStillChargesTheRepeatedLine() async {
        // Fire TV 26/11: with S2 not live yet, the same it-IT line was asked twice (charged twice).
        let fake = OryksaTvFakeBackend(voice: fakeMp3, fixedConfig: OryksaTvConfig(locale: "it-IT", fromServer: false))
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "it-IT", audioPlayer: player, cacheDirectory: tempCacheDir())
        let line = fresh("Ciao! Sono ORYKSA")
        await tv.presenter.say(line)
        await tv.presenter.say(line)
        XCTAssertEqual(fake.speakCalls, 2)
        XCTAssertEqual(fake.speakRequests.last?.cachedRev, "sim-1", "the revision the voice came with")
        XCTAssertEqual(player.plays, 2)
    }

    @MainActor
    func testAVoiceThatDoesNotMatchTheConfigurationMakesItReadAgain() async {
        // 26/11/2026 the pt-BR voice changed on the server while apps may be open.
        var serverRev = "old-rev"
        let fake = RevBackend(voice: fakeMp3, rev: { serverRev }) // the voices come as sim-1
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: FakePlayer(), cacheDirectory: tempCacheDir())
        let line = fresh("Uma frase")
        await tv.presenter.say(line)
        XCTAssertEqual(fake.reads, 1)
        serverRev = "sim-1"
        await tv.presenter.say(line)
        XCTAssertEqual(fake.reads, 2, "the voice came as sim-1 but the configuration said old-rev")
        XCTAssertEqual(fake.inner.speakCalls, 2, "charged each time")
        XCTAssertEqual(fake.inner.speakRequests.last?.cachedRev, "sim-1", "then kept under the new revision")
    }

    @MainActor
    func testTheConfigurationIsKeptTenMinutes() async throws {
        let fake = RevBackend(voice: nil, rev: { "r" })
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: FakePlayer(), cacheDirectory: tempCacheDir())
        _ = try await tv.config()
        _ = try await tv.config()
        XCTAssertEqual(fake.reads, 1)
        tv.configTTL = 0
        _ = try await tv.config()
        XCTAssertEqual(fake.reads, 2)
    }

    @MainActor
    func testWithoutVoiceTheSubtitlesShowOneByOneNeverARobotVoice() async {
        let fake = OryksaTvFakeBackend() // no voice
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "pt-PT", audioPlayer: player, cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 0.03 }
        let lines = LineLog(tv.presenter)
        await tv.presenter.say(fresh("Bem-vindo. Vamos começar"))
        XCTAssertEqual(fake.speakCalls, 1)
        XCTAssertEqual(player.plays, 0)
        XCTAssertEqual(lines.lines.count, 2)
        XCTAssertEqual(lines.lines.first, "Bem-vindo.")
    }

    @MainActor
    func testVoiceFalseShowsTheSubtitlesOnlyAtReadingSpeedWithNoSoundAndIsCharged() async {
        let server = OryksaTvFakeBackend(voice: fakeMp3)
        let player = FakePlayer()
        let tv = OryksaTv(backend: server, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 0.2 }
        var events: [String] = []
        tv.presenter.onStart = { events.append("start") }
        tv.presenter.onEnd = { events.append("end") }
        let lines = LineLog(tv.presenter)
        var phases = Set<OryksaPresenterPhase>()
        let sub = tv.presenter.$phase.sink { _ = phases.insert($0) }

        let start = Date()
        await tv.presenter.say("Encontramos alguém para você. Boa sorte!", voice: false)
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual(server.speakCalls, 1, "charged by the server, like a spoken line (owner, 26/11/2026)")
        XCTAssertEqual(server.speakRequests.first?.voice, false, "no voice asked for")
        XCTAssertTrue(player.loaded.isEmpty)
        XCTAssertEqual(player.plays, 0)
        XCTAssertEqual(lines.lines, ["Encontramos alguém para você.", "Boa sorte!"])
        XCTAssertGreaterThanOrEqual(elapsed, 0.39, "each line stays its reading time")
        XCTAssertTrue(phases.isSuperset(of: [.speaking, .idle]))
        XCTAssertEqual(events, ["start", "end"])
        XCTAssertFalse(tv.presenter.isBusy)
        XCTAssertEqual(tv.presenter.line, "")
        sub.cancel()
    }

    @MainActor
    func testASpokenLineTheServerDidNotCountIsNotShownAndPlaysNoSound() async {
        let fake = NotCounting(voice: fakeMp3)
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        let lines = LineLog(tv.presenter)
        let errors = ErrorLog(tv.presenter)
        await tv.presenter.say(fresh("Olá"))
        XCTAssertEqual(fake.inner.speakCalls, 1)
        XCTAssertEqual(player.plays, 0)
        XCTAssertTrue(lines.lines.isEmpty)
        XCTAssertEqual(errors.codes, ["not_counted"])
    }

    @MainActor
    func testARepeatedLineTheServerRefusesDoesNotPlayTheKeptVoice() async {
        let dir = tempCacheDir()
        let line = fresh("Boa noite")
        let first = OryksaTv(backend: OryksaTvFakeBackend(voice: fakeMp3), locale: "pt-BR", audioPlayer: FakePlayer(), cacheDirectory: dir)
        await first.presenter.say(line) // now kept on the device
        let refusing = NotCounting(voice: fakeMp3, refuse: true)
        let player = FakePlayer()
        let tv = OryksaTv(backend: refusing, locale: "pt-BR", audioPlayer: player, cacheDirectory: dir)
        tv.presenter.readingTime = { _ in 0.01 }
        let errors = ErrorLog(tv.presenter)
        await tv.presenter.say(line)
        XCTAssertEqual(refusing.inner.speakCalls, 1)
        XCTAssertEqual(refusing.inner.speakRequests.first?.cachedRev, "sim-1", "the device had it")
        XCTAssertEqual(player.plays, 0, "a kept line never plays without being charged")
        XCTAssertEqual((errors.errors.first as? OryksaError)?.status, 402)
        XCTAssertEqual(errors.errors.count, 1)
    }

    @MainActor
    func testStopEndsATextOnlyLineNowAndSayReturns() async {
        let tv = OryksaTv(backend: OryksaTvFakeBackend(), locale: "pt-PT", audioPlayer: FakePlayer(), cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 30 }
        let done = Task { @MainActor in await tv.presenter.say("Uma linha só para ler.", voice: false) }
        let speaking = await until(5) { tv.presenter.phase == .speaking }
        XCTAssertTrue(speaking)
        XCTAssertEqual(tv.presenter.line, "Uma linha só para ler.")
        tv.presenter.stop()
        let returned = await finishes(done, within: 2)
        XCTAssertTrue(returned)
        XCTAssertFalse(tv.presenter.isBusy)
        XCTAssertEqual(tv.presenter.line, "")
    }

    @MainActor
    func testASpokenLineGivenDuringATextOnlyOneReplacesIt() async {
        let fake = OryksaTvFakeBackend(voice: fakeMp3)
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 30 }
        let first = Task { @MainActor in await tv.presenter.say("Linha para ler.", voice: false) }
        let speaking = await until(5) { tv.presenter.phase == .speaking }
        XCTAssertTrue(speaking)
        await tv.presenter.say(fresh("Agora com voz"))
        let returned = await finishes(first, within: 2)
        XCTAssertTrue(returned)
        XCTAssertEqual(fake.speakCalls, 2, "the text-only line was charged, and the spoken one")
        XCTAssertEqual(player.plays, 1)
        XCTAssertFalse(tv.presenter.isBusy)
    }

    @MainActor
    func testSayGeneratedWithVoiceFalseChargesTheAiAnswerAndTheLineWithNoSound() async throws {
        let fake = OryksaTvFakeBackend(voice: fakeMp3)
        let player = FakePlayer()
        let tv = OryksaTv(backend: fake, locale: "pt-BR", audioPlayer: player, cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 0.01 }
        let text = try await tv.presenter.sayGenerated(instructions: "Say goodbye.", input: fresh("Ana"), voice: false)
        XCTAssertFalse(text.isEmpty)
        XCTAssertEqual(fake.aiCalls, 1)
        XCTAssertEqual(fake.speakCalls, 1)
        XCTAssertEqual(fake.speakRequests.first?.voice, false)
        XCTAssertEqual(player.plays, 0)
    }

    @MainActor
    func testStopEndsHerNowAndSayReturns() async {
        let fake = OryksaTvFakeBackend(voice: fakeMp3)
        let player = FakePlayer(playFor: 30)
        let tv = OryksaTv(backend: fake, locale: "pt-PT", audioPlayer: player, cacheDirectory: tempCacheDir())
        let done = Task { @MainActor in await tv.presenter.say(fresh("Uma fala muito longa")) }
        let speaking = await until(5) { tv.presenter.phase == .speaking }
        XCTAssertTrue(speaking)
        tv.presenter.stop()
        let returned = await finishes(done, within: 2)
        XCTAssertTrue(returned)
        XCTAssertFalse(tv.presenter.isBusy)
        XCTAssertGreaterThan(player.stops, 0)
    }

    @MainActor
    func testATextLongerThanTheServerLimitIsSentInPieces() async {
        let fake = OryksaTvFakeBackend(voice: fakeMp3, fixedConfig: OryksaTvConfig(
            locale: "pt-PT", voiceRev: "sim-limit", rules: OryksaTvRules(presenterMaxChars: 60)))
        let tv = OryksaTv(backend: fake, locale: "pt-PT", audioPlayer: FakePlayer(), cacheDirectory: tempCacheDir())
        let stamp = UUID().uuidString.prefix(6)
        await tv.presenter.say((0..<4).map { "Esta é a frase \($0) da apresentadora \(stamp)." }.joined(separator: " "))
        XCTAssertGreaterThan(fake.speakCalls, 1)
        for r in fake.speakRequests { XCTAssertLessThanOrEqual((r.text as NSString).length, 60) }
    }

    @MainActor
    func testSayGeneratedAsksTheAiInTheLocaleThenSpeaksTheAnswer() async throws {
        let fake = OryksaTvFakeBackend(voice: fakeMp3)
        let tv = OryksaTv(backend: fake, locale: "es-MX", audioPlayer: FakePlayer(), cacheDirectory: tempCacheDir())
        let text = try await tv.presenter.sayGenerated(instructions: "Announce the next round.", input: fresh("Round 2"))
        XCTAssertEqual(fake.aiCalls, 1)
        XCTAssertTrue(text.hasPrefix("(simulated)"))
        XCTAssertEqual(fake.speakCalls, 1)
    }

    // MARK: on the real client (HTTP simulated)

    private struct RealRun {
        let tts: [TVStub.Seen]
        let lines: [String]
        let errors: [String]
        let plays: Int
    }

    /// Says `text` on the real backend; `answer` answers `POST /v1/client/tts` (anything else is a 500,
    /// so the configuration is the fallback one).
    @MainActor
    private func runReal(_ text: String, voice: Bool, whisper: Bool = false,
                         answer: @escaping (TVStub.Seen) -> TVStub.Answer) async -> RealRun {
        TVStub.answer { s in
            s.path.hasSuffix("/client/tts") ? answer(s) : .json(#"{"error":{"code":"down"}}"#, 500)
        }
        let client = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), platform: OryksaTvPlatform.tvos.wire)
        let player = FakePlayer()
        let tv = OryksaTv(client: client, locale: "es-ES", audioPlayer: player, cacheDirectory: tempCacheDir())
        tv.presenter.readingTime = { _ in 0.01 }
        let lines = LineLog(tv.presenter)
        let errors = ErrorLog(tv.presenter)
        await tv.presenter.say(text, whisper: whisper, voice: voice)
        return RealRun(tts: TVStub.seen.filter { $0.path.hasSuffix("/client/tts") }, lines: lines.lines,
                       errors: errors.codes, plays: player.plays)
    }

    @MainActor
    func testRealVoiceFalseAsksWithVoiceFalseAndTheCountedSubtitlesShow() async {
        let r = await runReal(fresh("Hola. Hoy hablamos de viajes"), voice: false) { _ in
            .noContent(["X-ORYKSA-Interactions-Spent": "1", "X-ORYKSA-Locale": "es-ES", "X-ORYKSA-Voice-Status": "captions"])
        }
        XCTAssertEqual(r.tts.count, 1)
        let b = r.tts.first?.json ?? [:]
        XCTAssertEqual(b["voice"] as? Bool, false)
        XCTAssertEqual(b["purpose"] as? String, "presenter")
        XCTAssertEqual(b["platform"] as? String, "tvos")
        XCTAssertEqual(b["locale"] as? String, "es-ES")
        XCTAssertNil(b["cached"], "a subtitles-only line never says it is kept")
        XCTAssertEqual(r.tts.first?.method, "POST")
        XCTAssertEqual(r.tts.first?.path, "/v1/client/tts")
        XCTAssertEqual(r.lines.first, "Hola.")
        XCTAssertEqual(r.plays, 0)
        XCTAssertTrue(r.errors.isEmpty)
    }

    @MainActor
    func testRealALineTheServerDidNotCountIsNotShown() async {
        let r = await runReal(fresh("Hola. Hoy hablamos de viajes"), voice: false) { _ in .noContent() }
        XCTAssertEqual(r.tts.count, 1)
        XCTAssertTrue(r.lines.isEmpty)
        XCTAssertEqual(r.errors, ["not_counted"])
    }

    @MainActor
    func testRealASpokenLineWithAVoiceButNoSpentHeaderIsNotShownNorPlayed() async {
        let r = await runReal(fresh("Hola"), voice: true, whisper: true) { _ in .audio([0xFF, 0xFB, 1, 2]) }
        XCTAssertEqual(r.tts.count, 1)
        XCTAssertEqual(r.tts.first?.json["whisper"] as? Bool, true)
        XCTAssertNil(r.tts.first?.json["voice"], "a spoken line does not send voice")
        XCTAssertEqual(r.plays, 0)
        XCTAssertTrue(r.lines.isEmpty)
        XCTAssertEqual(r.errors, ["not_counted"])
    }

    @MainActor
    func testRealASpentHeaderUnderOneIsNotCounted() async {
        let r = await runReal(fresh("Hola"), voice: false) { _ in .noContent(["X-ORYKSA-Interactions-Spent": "0"]) }
        XCTAssertTrue(r.lines.isEmpty)
        XCTAssertEqual(r.errors, ["not_counted"])
    }

    @MainActor
    func testRealNoInteractionsLeftShowsNothingAndTheNextPiecesAreNotAsked() async {
        let long = (0..<30).map { "Frase número \($0) de un texto largo para la presentadora." }.joined(separator: " ")
        let r = await runReal(long, voice: true) { _ in
            .json(#"{"error":{"code":"interactions_exhausted","message":"No interactions left."}}"#, 402)
        }
        XCTAssertEqual(r.tts.count, 1, "she stops at the first piece not counted")
        XCTAssertTrue(r.lines.isEmpty)
        XCTAssertEqual(r.errors, ["interactions_exhausted"])
    }

    @MainActor
    func testRealANetworkErrorShowsNothing() async {
        let r = await runReal(fresh("Hola"), voice: true) { _ in .network() }
        XCTAssertTrue(r.lines.isEmpty)
        XCTAssertFalse(r.errors.isEmpty)
    }

    @MainActor
    func testRealTheSameLineAgainSendsCachedWithItsVoiceRevAndPlaysTheKeptVoice() async {
        TVStub.answer { s in
            guard s.path.hasSuffix("/client/tts") else { return .json(#"{"error":{"code":"down"}}"#, 500) }
            if (s.json["cached"] as? Bool) == true {
                return .noContent(["X-ORYKSA-Interactions-Spent": "1", "X-ORYKSA-Voice-Status": "cached",
                                   "X-ORYKSA-Voice-Rev": "rev-a", "X-ORYKSA-Locale": "es-ES"])
            }
            return .audio([0xFF, 0xFB, 1, 2], headers: ["X-ORYKSA-Interactions-Spent": "2", "X-ORYKSA-Voice-Rev": "rev-a",
                                                         "X-ORYKSA-Locale": "es-ES"])
        }
        let client = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), platform: OryksaTvPlatform.tvos.wire)
        let player = FakePlayer()
        let tv = OryksaTv(client: client, locale: "es-ES", audioPlayer: player, cacheDirectory: tempCacheDir())
        let errors = ErrorLog(tv.presenter)
        let line = fresh("Hola, soy ORYKSA")
        await tv.presenter.say(line)
        await tv.presenter.say(line)
        let tts = TVStub.seen.filter { $0.path.hasSuffix("/client/tts") }
        XCTAssertEqual(tts.count, 2, "asked and charged each time")
        XCTAssertNil(tts.first?.json["cached"])
        XCTAssertEqual(tts.last?.json["cached"] as? Bool, true)
        XCTAssertEqual(tts.last?.json["voice_rev"] as? String, "rev-a")
        XCTAssertEqual(player.plays, 2)
        XCTAssertEqual(player.loaded.count, 2)
        XCTAssertEqual(player.loaded.first, player.loaded.last, "the kept voice plays the second time")
        XCTAssertTrue(errors.errors.isEmpty)
    }
}

// TV SDK (26/11/2026): the contract approved by the MASTER, section 9 of sdk-tv/DESENHO.md (port of the
// Flutter test/tv_models_test.dart).
import Foundation
import XCTest
@testable import OryksaTV

private func json(_ s: String) -> [String: Any] {
    ((try? JSONSerialization.jsonObject(with: Data(s.utf8))) as? [String: Any]) ?? [:]
}

final class TVModelsTests: XCTestCase {
    // MARK: locale

    func testLocalesAreNormalisedToBcp47WithAHyphen() {
        XCTAssertEqual(oryksaTvNormalizeLocale("pt_br"), "pt-BR")
        XCTAssertEqual(oryksaTvNormalizeLocale("ES-419"), "es-419")
        XCTAssertEqual(oryksaTvNormalizeLocale("zh_hant_tw"), "zh-Hant-TW")
        XCTAssertEqual(oryksaTvNormalizeLocale("  "), "")
        XCTAssertEqual(oryksaTvLocaleTag(Locale(identifier: "pt_PT")), "pt-PT")
        XCTAssertEqual(oryksaTvLocaleTag(Locale(identifier: "fr")), "fr")
        XCTAssertFalse(oryksaTvDeviceLocale().isEmpty)
    }

    func testTheChatKeepsItsOldLanguageCodes() {
        XCTAssertEqual(oryksaTvChatLang("pt-BR"), "br")
        XCTAssertEqual(oryksaTvChatLang("pt-PT"), "pt")
        XCTAssertEqual(oryksaTvChatLang("es-419"), "es")
        XCTAssertEqual(oryksaTvChatLang("en-GB"), "en")
        XCTAssertEqual(oryksaTvChatLang("de-DE"), "de")
        XCTAssertEqual(oryksaTvChatLang(""), "")
    }

    func testTheSimulatedServerPicksTheSameLocalesAsTheApprovedTable() {
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("pt-BR"), "pt-BR")
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("pt-AO"), "pt-PT")
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("es-MX"), "es-419")
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("es-ES"), "es-ES")
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("fr-CA"), "fr-FR")
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("en-GB"), "en-GB")
        XCTAssertEqual(OryksaTvFakeBackend.resolveLocale("it-IT"), "en-US")
    }

    // MARK: configuration (GET /client/agent?locale=, block tv)

    func testReadsTheWholeTvBlockOfTheContract() {
        let c = OryksaTvConfig.fromAgentJSON(json("""
        {"name":"ORYKSA","avatar":"https://x/a.png","tv":{
          "locale":"pt-BR","voice_rev":"v7f3a",
          "presenter":{"name":"ORYKSA","avatar":"https://x/p.png"},
          "texts":{"pair_step_code":"Ou abra {url} e digite {code}","close":"Fechar"},
          "suggestions":["Como funciona?"," ","O que você pode fazer?"],
          "actions":[
            {"id":"phone_voice","kind":"phone_voice","label":"Falar pelo celular"},
            {"id":"help","kind":"message","label":"Ajuda","message":"Preciso de ajuda"},
            {"id":"bad","kind":"message","label":"Sem mensagem"},
            {"id":"new","kind":"teleport","label":"Novo"}],
          "rules":{"phone_voice":true,"tv_mic":"off","speak_replies":false,"presenter_max_chars":300}}}
        """), requestedLocale: "pt-BR")
        XCTAssertTrue(c.fromServer)
        XCTAssertEqual(c.locale, "pt-BR")
        XCTAssertEqual(c.voiceRev, "v7f3a")
        XCTAssertEqual(c.presenterAvatar, "https://x/p.png")
        XCTAssertEqual(c.suggestions, ["Como funciona?", "O que você pode fazer?"])
        XCTAssertEqual(c.actions.map(\.id), ["phone_voice", "help"])
        XCTAssertEqual(c.actions.first?.kind, .phoneVoice)
        XCTAssertEqual(c.actions.last?.message, "Preciso de ajuda")
        XCTAssertEqual(c.rules.tvMic, "off")
        XCTAssertFalse(c.rules.speakReplies)
        XCTAssertEqual(c.rules.presenterMaxChars, 300)
        XCTAssertEqual(c.texts.get("pair_step_code", ["url": "oryksa.com/tv", "code": "K7Q2MZ"]), "Ou abra oryksa.com/tv e digite K7Q2MZ")
        XCTAssertEqual(c.texts.get("close"), "Fechar")
        XCTAssertEqual(c.texts.get("retry"), "Try again", "a missing key uses the English fallback")
    }

    func testAnOlderServerWithoutTvBlockStillWorksWithTheEnglishFallback() {
        let c = OryksaTvConfig.fromAgentJSON(json(#"{"name":"Ana","avatar":"https://x/a.png"}"#), requestedLocale: "fr_ca")
        XCTAssertFalse(c.fromServer)
        XCTAssertEqual(c.locale, "fr-CA")
        XCTAssertNil(c.voiceRev)
        XCTAssertEqual(c.presenterName, "Ana")
        XCTAssertEqual(c.presenterAvatar, "https://x/a.png")
        XCTAssertTrue(c.rules.phoneVoice)
        XCTAssertEqual(c.rules.presenterMaxChars, 600)
        XCTAssertEqual(c.texts.get("pair_title"), "Talk on your phone")
    }

    func testATooSmallPresenterLimitKeepsTheDefault() {
        XCTAssertEqual(OryksaTvRules.from(["presenter_max_chars": 10]).presenterMaxChars, 600)
        XCTAssertEqual(OryksaTvRules.from(["phone_voice": false]).phoneVoice, false)
        XCTAssertEqual(OryksaTvRules.from([:]).tvMic, "auto")
    }

    // MARK: pairing (POST /client/tv/pair and the events)

    func testReadsThePairing() throws {
        let p = try OryksaPairing.from(json("""
        {"pair_id":"tvp_9f2c41d0","code":"K7Q2MZ","url":"https://oryksa.com/tv?c=K7Q2MZ","short_url":"oryksa.com/tv",
         "qr_png_url":"https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png","expires_in":300}
        """))
        XCTAssertEqual(p.code, "K7Q2MZ")
        XCTAssertEqual(p.shortUrl, "oryksa.com/tv")
        XCTAssertEqual(p.expiresIn, 300)
        XCTAssertEqual(p.expiresAt.timeIntervalSince(p.createdAt), 300, accuracy: 0.001)
    }

    func testAPairingWithoutIdOrCodeIsRefused() {
        XCTAssertThrowsError(try OryksaPairing.from(["code": "X"]))
        XCTAssertThrowsError(try OryksaPairing.from(["pair_id": "x"]))
    }

    func testReadsAPageOfEventsNextFollowsTheHighestSeqAndUnknownTypesAreKept() {
        let page = OryksaPhoneEventsPage.from(json("""
        {"state":"paired","next":2,"events":[
          {"seq":1,"type":"paired"},
          {"seq":2,"type":"listening"},
          {"seq":3,"type":"text","text":"Como funciona?","lang":"pt-BR","final":true},
          {"seq":4,"type":"hologram"}]}
        """), after: 0)
        XCTAssertEqual(page.state, "paired")
        XCTAssertEqual(page.next, 4)
        XCTAssertEqual(page.events.map(\.type), [.paired, .listening, .text, .unknown])
        XCTAssertEqual(page.events[2].text, "Como funciona?")
        XCTAssertEqual(page.events[2].lang, "pt-BR")
        XCTAssertTrue(page.events[2].isFinal)
    }

    func testTheRealS3AnswerObjectPhoneAndEventsUrlAreReadOrIgnored() throws {
        let page = OryksaPhoneEventsPage.from(json(#"{"object":"tv_pair_events","state":"paired","phone":true,"next":1,"events":[{"seq":1,"type":"paired"}]}"#))
        XCTAssertEqual(page.phoneConnected, true)
        XCTAssertNil(OryksaPhoneEventsPage.from(json(#"{"state":"waiting"}"#)).phoneConnected)
        let p = try OryksaPairing.from(json("""
        {"pair_id":"tvp_0123456789ab","code":"K7Q2MZ","url":"https://oryksa.com/tv?c=K7Q2MZ","short_url":"oryksa.com/tv",
         "qr_png_url":"https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png","expires_in":300,
         "events_url":"/v1/client/tv/pair/tvp_0123456789ab/events"}
        """))
        XCTAssertEqual(p.pairId, "tvp_0123456789ab")
    }

    func testAnEmptyLongPollAnswerKeepsAfter() {
        let page = OryksaPhoneEventsPage.from(json(#"{"state":"waiting","events":[]}"#), after: 7)
        XCTAssertEqual(page.next, 7)
        XCTAssertTrue(page.events.isEmpty)
    }

    // MARK: text for the voice and the subtitles

    func testALongTextIsSplitUnderTheLimitAtTheEndOfSentences() {
        let s = (0..<12).map { "Esta é a frase número \($0) da apresentadora." }.joined(separator: " ")
        let parts = oryksaTvSplitForSpeech(s, max: 120)
        XCTAssertGreaterThan(parts.count, 1)
        for p in parts {
            XCTAssertLessThanOrEqual((p as NSString).length, 120)
            XCTAssertTrue(p.hasSuffix("."))
        }
        XCTAssertEqual(parts.joined(separator: " "), s)
    }

    func testASentenceLongerThanTheLimitIsCutAtACommaOrASpace() {
        let s = "Uma frase muito comprida, " + String(repeating: "com muitas palavras ", count: 20) + "e um fim."
        let parts = oryksaTvSplitForSpeech(s, max: 80)
        XCTAssertGreaterThan(parts.count, 1)
        for p in parts { XCTAssertLessThanOrEqual((p as NSString).length, 80) }
        XCTAssertEqual(oryksaTvCollapse(parts.joined(separator: " ")), oryksaTvCollapse(s))
    }

    func testSubtitlesOneSentencePerLine() {
        XCTAssertEqual(oryksaTvSubtitleLines("Olá! Sou a ORYKSA. Vamos começar?"), ["Olá!", "Sou a ORYKSA.", "Vamos começar?"])
        XCTAssertEqual(oryksaTvSubtitleLines("Fim… E depois"), ["Fim…", "E depois"])
    }

    func testReadingTimeAbout14CharactersASecondNeverUnder1Point8Seconds() {
        XCTAssertEqual(oryksaTvReadingTime("Olá!"), 1.8, accuracy: 0.0001)
        XCTAssertEqual(oryksaTvReadingTime(String(repeating: "a", count: 70)), 5.0, accuracy: 0.0001)
    }

    func testTheTvPlatformsOfTheContract() {
        XCTAssertEqual(OryksaTvPlatform.allCases.map(\.wire), ["android_tv", "fire_tv", "vega", "tizen", "webos", "vidaa", "tvos", "roku"])
    }

    func testTheSampleTextsHaveEveryKeyOfTheContractAndNeverMixPortuguese() {
        let keys = Set(OryksaTvTexts.fallback.keys)
        XCTAssertEqual(keys.count, 18, "the 18 keys of tv.texts")
        for l in ["en", "pt-PT", "pt-BR"] {
            XCTAssertEqual(Set(OryksaTvSimulated.sampleTexts(for: l).keys), keys, l)
        }
        let br = OryksaTvSimulated.sampleTexts(for: "pt-BR").values.joined(separator: " ")
        let pt = OryksaTvSimulated.sampleTexts(for: "pt-PT").values.joined(separator: " ")
        for w in ["telemóvel", "ecrã", "comando"] { XCTAssertFalse(br.contains(w), w) }
        for w in ["celular", "você", "tela"] { XCTAssertFalse(pt.contains(w), w) }
    }
}

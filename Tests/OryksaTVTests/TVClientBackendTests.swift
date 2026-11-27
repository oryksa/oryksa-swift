// The real backend against the contract of sdk-tv/DESENHO.md section 9, with the HTTP simulated (port
// of the Flutter test/tv_client_backend_test.dart). This proves the requests the SDK sends and how it
// reads the answers; it does NOT prove the ORYKSA server.
import Foundation
import XCTest
@testable import OryksaTV

/// Counts in a closure that runs on the URL loading thread.
private final class Counter {
    private let lock = NSLock()
    private var n = 0
    func next() -> Int { lock.lock(); defer { lock.unlock() }; n += 1; return n }
    var value: Int { lock.lock(); defer { lock.unlock() }; return n }
}

final class TVClientBackendTests: XCTestCase {
    // MARK: platform (S5) and the public session (S4)

    func testATvPlatformGoesInTheChatAndInAiAndTheDefaultIsThisDevice() async throws {
        TVStub.answer { s in
            s.path.hasSuffix("/client/ai") ? .json(#"{"text":"ok"}"#) : .json(#"{"status":"replied","reply":"ok"}"#)
        }
        let tvClient = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), platform: OryksaTvPlatform.fireTv.wire)
        XCTAssertEqual(tvClient.platform, "fire_tv")
        _ = try await tvClient.send("olá")
        _ = try await tvClient.ai(input: "x")
        XCTAssertEqual(TVStub.seen.first { $0.path == "/v1/client/chat" }?.json["platform"] as? String, "fire_tv")
        XCTAssertEqual(TVStub.seen.first { $0.path == "/v1/client/ai" }?.json["platform"] as? String, "fire_tv")

        TVStub.answer { _ in .json(#"{"status":"replied","reply":"ok"}"#) }
        let here = OryksaClient(token: "oryk_cs_t", session: TVStub.session())
        #if os(tvOS)
        XCTAssertEqual(here.platform, "tvos", "on Apple TV the client says tvos by itself")
        #else
        XCTAssertEqual(here.platform, "ios")
        #endif
        _ = try await here.send("olá")
        XCTAssertEqual(TVStub.seen.first?.json["platform"] as? String, here.platform)
    }

    func testThePublicSessionSendsPlatformAndAppIdOnlyWhenGiven() async throws {
        TVStub.answer { s in
            if s.path.hasSuffix("/public/sessions") { return .json(#"{"object":"client_session","client_token":"oryk_cs_new"}"#, 201) }
            return .json(#"{"status":"replied","reply":"ok"}"#)
        }
        let tv = OryksaClient.public(chatToken: "oryk_pub_x", conversationId: "c1", session: TVStub.session(),
                                     platform: "tvos", appId: "com.example.tv")
        _ = try await tv.send("olá")
        let session = try XCTUnwrap(TVStub.seen.first { $0.path == "/v1/public/sessions" })
        XCTAssertEqual(session.method, "POST")
        XCTAssertNil(session.header("Authorization"), "the public session needs no token")
        XCTAssertEqual(session.json["widget_token"] as? String, "oryk_pub_x")
        XCTAssertEqual(session.json["conversation_id"] as? String, "c1")
        XCTAssertEqual(session.json["platform"] as? String, "tvos")
        XCTAssertEqual(session.json["app_id"] as? String, "com.example.tv")
        XCTAssertEqual(tv.platform, "tvos")
        let chat = try XCTUnwrap(TVStub.seen.first { $0.path == "/v1/client/chat" })
        XCTAssertEqual(chat.header("Authorization"), "Bearer oryk_cs_new")

        TVStub.answer { s in
            if s.path.hasSuffix("/public/sessions") { return .json(#"{"client_token":"oryk_cs_new"}"#, 201) }
            return .json(#"{"status":"replied","reply":"ok"}"#)
        }
        let plain = OryksaClient.public(chatToken: "oryk_pub_x", conversationId: "c1", session: TVStub.session())
        _ = try await plain.send("olá")
        let s2 = try XCTUnwrap(TVStub.seen.first { $0.path == "/v1/public/sessions" })
        XCTAssertNil(s2.json["platform"])
        XCTAssertNil(s2.json["app_id"])
    }

    func testARefusedChatTokenIsReported() async {
        TVStub.answer { _ in .json(#"{"error":{"code":"not_found","message":"Unknown widget_token."}}"#, 404) }
        let c = OryksaClient.public(chatToken: "oryk_pub_x", session: TVStub.session())
        do {
            _ = try await c.send("hi")
            XCTFail("a refused chat token must throw")
        } catch let e as OryksaError {
            XCTAssertEqual(e.code, "not_found")
        } catch {
            XCTFail("unexpected \(error)")
        }
    }

    // MARK: presenter voice (S1)

    @MainActor
    func testTheVoiceRequestSendsTextLocalePurposeAndPlatformAndReadsTheHeaders() async throws {
        TVStub.answer { _ in
            .audio([1, 2, 3], headers: ["X-ORYKSA-Locale": "es-419", "X-ORYKSA-Voice-Rev": "a1b2c3d4e5f6",
                                        "X-ORYKSA-Interactions-Spent": "1"])
        }
        let c = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), platform: "fire_tv")
        let sp = try await OryksaTvClientBackend(c).speak("Hola", locale: "es_MX")
        let s = try XCTUnwrap(TVStub.seen.first)
        XCTAssertEqual(s.method, "POST")
        XCTAssertEqual(s.path, "/v1/client/tts")
        XCTAssertEqual(Set(s.json.keys), ["text", "locale", "purpose", "platform"])
        XCTAssertEqual(s.json["text"] as? String, "Hola")
        XCTAssertEqual(s.json["locale"] as? String, "es-MX")
        XCTAssertEqual(s.json["purpose"] as? String, "presenter")
        XCTAssertEqual(s.json["platform"] as? String, "fire_tv")
        let speech = try XCTUnwrap(sp)
        XCTAssertEqual(speech.data, Data([1, 2, 3]))
        XCTAssertEqual(speech.locale, "es-419")
        XCTAssertEqual(speech.voiceRev, "a1b2c3d4e5f6")
        XCTAssertEqual(speech.interactionsSpent, 1)
        XCTAssertEqual(speech.status, 200)
    }

    @MainActor
    func testCachedAndVoiceFalseGoInTheVoiceRequest() async throws {
        TVStub.answer { _ in .noContent(["X-ORYKSA-Interactions-Spent": "2", "X-ORYKSA-Voice-Status": "cached"]) }
        let c = OryksaClient(token: "oryk_cs_t", session: TVStub.session())
        let b = OryksaTvClientBackend(c)
        let kept = try await b.speak("Olá", locale: "pt-BR", whisper: false, voice: true, cachedRev: "v7f3a")
        XCTAssertEqual(TVStub.seen.last?.json["cached"] as? Bool, true)
        XCTAssertEqual(TVStub.seen.last?.json["voice_rev"] as? String, "v7f3a")
        XCTAssertNil(TVStub.seen.last?.json["voice"])
        XCTAssertEqual(kept?.status, 204)
        XCTAssertEqual(kept?.voiceStatus, "cached")
        XCTAssertEqual(kept?.interactionsSpent, 2, "the number is the server's, whatever it is")
        XCTAssertEqual(kept?.data.isEmpty, true)

        _ = try await b.speak("Olá", locale: "pt-BR", whisper: true, voice: false, cachedRev: "v7f3a")
        XCTAssertEqual(TVStub.seen.last?.json["voice"] as? Bool, false)
        XCTAssertEqual(TVStub.seen.last?.json["whisper"] as? Bool, true)
        XCTAssertNil(TVStub.seen.last?.json["cached"], "subtitles only never sends cached")
        XCTAssertNil(TVStub.seen.last?.json["voice_rev"])
    }

    @MainActor
    func testVoiceUnavailableGivesNilAndOtherErrorsThrow() async throws {
        TVStub.answer { _ in .json(#"{"error":{"code":"voice_unavailable","message":"no voice"}}"#, 503) }
        let b = OryksaTvClientBackend(OryksaClient(token: "oryk_cs_t", session: TVStub.session()))
        let none = try await b.speak("Olá", locale: "pt-PT")
        XCTAssertNil(none)
        TVStub.answer { _ in .json(#"{"error":{"code":"text_too_long","message":"too long"}}"#, 413) }
        do {
            _ = try await b.speak("Olá", locale: "pt-PT")
            XCTFail("text_too_long must throw")
        } catch let e as OryksaError {
            XCTAssertEqual(e.code, "text_too_long")
            XCTAssertEqual(e.status, 413)
        }
    }

    @MainActor
    func testAnExpiredTokenIsRenewedOnceForTheVoice() async throws {
        let calls = Counter()
        let tokens = Counter()
        TVStub.answer { s in
            _ = calls.next()
            if s.header("Authorization") == "Bearer oryk_cs_1" {
                return .json(#"{"error":{"code":"session_expired","message":"expired"}}"#, 401)
            }
            return .audio([9], headers: ["X-ORYKSA-Interactions-Spent": "1"])
        }
        let c = OryksaClient(getToken: { "oryk_cs_\(tokens.next())" }, session: TVStub.session())
        let sp = try await OryksaTvClientBackend(c).speak("Olá", locale: "pt-PT")
        XCTAssertEqual(sp?.data, Data([9]))
        XCTAssertEqual(calls.value, 2)
        XCTAssertEqual(tokens.value, 2)
    }

    // MARK: configuration (S2) and chat

    @MainActor
    func testTheConfigurationComesFromClientAgentWithTheLocale() async throws {
        TVStub.answer { _ in
            .json(#"{"name":"ORYKSA","tv":{"locale":"pt-BR","voice_rev":"v1","texts":{"close":"Fechar"}}}"#)
        }
        let cfg = try await OryksaTvClientBackend(OryksaClient(token: "oryk_cs_t", session: TVStub.session())).config("pt_BR")
        let s = try XCTUnwrap(TVStub.seen.first)
        XCTAssertEqual(s.method, "GET")
        XCTAssertEqual(s.path, "/v1/client/agent")
        XCTAssertEqual(s.query("locale"), "pt-BR")
        XCTAssertEqual(cfg.locale, "pt-BR")
        XCTAssertEqual(cfg.voiceRev, "v1")
        XCTAssertEqual(cfg.texts.get("close"), "Fechar")
    }

    @MainActor
    func testTheChatOfThePanelSendsTheOldLanguageCodeAndWaitsForTheReply() async throws {
        TVStub.answer { _ in .json(#"{"status":"replied","reply":"Olá!","speech":"Olá!"}"#) }
        let c = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), platform: "tvos")
        let r = try await OryksaTvClientBackend(c).chat("oi", locale: "pt-BR", appContext: OryksaAppContext(screen: "home"), voice: true)
        let b = TVStub.seen.first?.json ?? [:]
        XCTAssertEqual(b["lang"] as? String, "br")
        XCTAssertEqual(b["voice"] as? Bool, true)
        XCTAssertEqual(b["platform"] as? String, "tvos")
        XCTAssertEqual((b["app_context"] as? [String: Any])?["screen"] as? String, "home")
        XCTAssertEqual(r.reply, "Olá!")
        XCTAssertEqual(r.speech, "Olá!")
    }

    // MARK: phone pairing (S3)

    @MainActor
    func testPairingCreateLongPollEventsAndClose() async throws {
        TVStub.answer { s in
            switch s.method {
            case "POST":
                return .json(#"{"pair_id":"tvp_9f2c41d0","code":"K7Q2MZ","url":"https://oryksa.com/tv?c=K7Q2MZ","short_url":"oryksa.com/tv","qr_png_url":"https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png","expires_in":300}"#, 201)
            case "GET":
                return .json(#"{"state":"paired","next":3,"events":[{"seq":3,"type":"text","text":"Olá","lang":"pt-PT","final":true}]}"#)
            default:
                return .noContent()
            }
        }
        let c = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), platform: "tvos", timeout: 20)
        let b = OryksaTvClientBackend(c)
        let p = try await b.pair("pt_PT")
        let seen0 = TVStub.seen[0]
        XCTAssertEqual(seen0.path, "/v1/client/tv/pair")
        XCTAssertEqual(seen0.json["locale"] as? String, "pt-PT")
        XCTAssertEqual(seen0.json["platform"] as? String, "tvos")
        XCTAssertEqual(Set(seen0.json.keys), ["locale", "platform"])
        XCTAssertEqual(p.pairId, "tvp_9f2c41d0")
        XCTAssertEqual(p.qrPngUrl, "https://api.oryksa.com/v1/public/tv/qr/K7Q2MZ.png")

        let page = try await b.phoneEvents(p.pairId, after: 2, wait: 25)
        let seen1 = TVStub.seen[1]
        XCTAssertEqual(seen1.method, "GET")
        XCTAssertEqual(seen1.path, "/v1/client/tv/pair/tvp_9f2c41d0/events")
        XCTAssertEqual(seen1.query("after"), "2")
        XCTAssertEqual(seen1.query("wait"), "15", "kept 5 s under the client time limit of 20 s")
        XCTAssertEqual(page.events.first?.text, "Olá")
        XCTAssertEqual(page.next, 3)

        try await b.unpair(p.pairId)
        let seen2 = TVStub.seen[2]
        XCTAssertEqual(seen2.method, "DELETE")
        XCTAssertEqual(seen2.path, "/v1/client/tv/pair/tvp_9f2c41d0")
    }

    @MainActor
    func testWaitIsNeverOverThirtySeconds() async throws {
        TVStub.answer { _ in .json(#"{"state":"waiting","next":0,"events":[]}"#) }
        let c = OryksaClient(token: "oryk_cs_t", session: TVStub.session(), timeout: 120)
        _ = try await OryksaTvClientBackend(c).phoneEvents("tvp_x", after: 0, wait: 90)
        XCTAssertEqual(TVStub.seen.first?.query("wait"), "30")
    }

    @MainActor
    func testTheSimulatedServerAnswers410AfterTheEndAsTheRealOne() async throws {
        let fake = OryksaTvFakeBackend()
        let p = try await fake.pair("pt-PT")
        fake.expire()
        let page = try await fake.phoneEvents(p.pairId)
        XCTAssertEqual(page.state, "expired")
        do {
            _ = try await fake.phoneEvents(p.pairId, after: page.next)
            XCTFail("after the end it must be 410")
        } catch let e as OryksaError {
            XCTAssertEqual(e.code, "pair_expired")
            XCTAssertEqual(e.status, 410)
        }
    }
}

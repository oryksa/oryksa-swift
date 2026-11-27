// The phone voice on the SIMULATED backend (port of the Flutter "phone voice" tests): this proves the
// SDK logic (QR, events, stop), not the ORYKSA server or its phone page.
import Combine
import Foundation
import XCTest
@testable import OryksaTV

/// A server that cannot make a pairing.
@MainActor
private final class NoPairing: WrapBackend {
    init() { super.init(OryksaTvFakeBackend()) }
    override func pair(_ locale: String) async throws -> OryksaPairing {
        throw OryksaError(status: 403, code: "phone_voice_disabled", message: "The phone voice is off.")
    }
}

/// A server that lost the pairing (404).
@MainActor
private final class LostPairing: WrapBackend {
    init() { super.init(OryksaTvFakeBackend()) }
    override func phoneEvents(_ pairId: String, after: Int, wait: TimeInterval) async throws -> OryksaPhoneEventsPage {
        throw OryksaError(status: 404, code: "pair_not_found", message: "No such pairing.")
    }
}

final class TVPhoneVoiceTests: XCTestCase {
    @MainActor
    private func makeTv(_ backend: OryksaTvBackend) -> OryksaTv {
        let tv = OryksaTv(backend: backend, locale: "pt-PT", audioPlayer: FakePlayer(), cacheDirectory: tempCacheDir())
        tv.phoneVoice.pollWait = 0.05
        tv.phoneVoice.retryPause = 0.01
        return tv
    }

    @MainActor
    func testQrThePhoneConnectsWhatThePersonSaysArrivesAsTextStopEndsThePairing() async {
        let fake = OryksaTvFakeBackend()
        let tv = makeTv(fake)
        let pv = tv.phoneVoice
        var heard: [String] = []
        var onText: [String] = []
        let sub = pv.texts.sink { heard.append($0) }
        pv.onText = { onText.append($0) }

        await pv.start()
        XCTAssertEqual(pv.state, .waiting)
        XCTAssertEqual(pv.pairing?.code, "K7Q2MZ")
        XCTAssertTrue(pv.isActive)

        fake.phoneConnects()
        let paired = await until { pv.state == .paired }
        XCTAssertTrue(paired)
        fake.phoneSays("Como funciona o encontro?")
        let got = await until { !heard.isEmpty }
        XCTAssertTrue(got)
        XCTAssertEqual(heard, ["Como funciona o encontro?"])
        XCTAssertEqual(onText, ["Como funciona o encontro?"])
        XCTAssertEqual(pv.lastText, "Como funciona o encontro?")

        fake.phoneLeaves()
        let left = await until { pv.state == .phoneLeft }
        XCTAssertTrue(left)

        await pv.stop()
        XCTAssertEqual(pv.state, .idle)
        XCTAssertNil(pv.pairing)
        XCTAssertEqual(fake.unpaired, [OryksaTvFakeBackend.pairIdOf(1)])
        sub.cancel()
    }

    @MainActor
    func testAnExpiredCodeStopsTheWaitingAndRestartGivesANewCode() async {
        let fake = OryksaTvFakeBackend()
        let tv = makeTv(fake)
        let pv = tv.phoneVoice
        await pv.start()
        fake.expire()
        let expired = await until { pv.state == .expired }
        XCTAssertTrue(expired)
        XCTAssertFalse(pv.isActive)
        await pv.restart()
        XCTAssertEqual(pv.state, .waiting)
        XCTAssertEqual(pv.pairing?.code, "H4PRWX")
        XCTAssertEqual(fake.unpaired, [OryksaTvFakeBackend.pairIdOf(1)])
        await pv.stop()
    }

    @MainActor
    func testAPairingTheServerRefusesEndsInErrorWithTheReason() async {
        let tv = makeTv(NoPairing())
        await tv.phoneVoice.start()
        XCTAssertEqual(tv.phoneVoice.state, .error)
        XCTAssertEqual((tv.phoneVoice.lastError as? OryksaError)?.code, "phone_voice_disabled")
        XCTAssertFalse(tv.phoneVoice.isActive)
    }

    @MainActor
    func testAPairingTheServerLostIsClosed() async {
        let tv = makeTv(LostPairing())
        await tv.phoneVoice.start()
        let closed = await until { tv.phoneVoice.state == .closed }
        XCTAssertTrue(closed)
    }

    @MainActor
    func testStartTwiceMakesOnePairing() async {
        let fake = OryksaTvFakeBackend()
        let tv = makeTv(fake)
        await tv.phoneVoice.start()
        await tv.phoneVoice.start()
        XCTAssertEqual(tv.phoneVoice.pairing?.pairId, OryksaTvFakeBackend.pairIdOf(1))
        await tv.phoneVoice.stop()
    }
}

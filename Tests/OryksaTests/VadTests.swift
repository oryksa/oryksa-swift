import XCTest
@testable import Oryksa

/// The audio tests of the ORYKSA app (`test/*.dart`), ported with the engine. Real recordings
/// (`voice/*.wav`) and synthetic sound: a bird, the TV, typing, a plane, her own echo must NOT cut
/// her off; "Para" and "Espera" MUST.
final class VadTests: XCTestCase {

    // ------------------------------------------------------------------ helpers
    /// Small deterministic random generator (the tests must not depend on the platform RNG).
    struct Lcg { var s: UInt64; mutating func next() -> Double { s = s &* 6364136223846793005 &+ 1442695040888963407; return Double(s >> 11) / Double(1 << 53) } }

    /// `ms` of sound at exactly `nivel` RMS (16 kHz PCM16). With `tom` it is periodic like a voice.
    func pedaco(_ nivel: Double, ms: Int = 100, tom: Bool = true, hz: Double = 120, seed: UInt64 = 7) -> Data {
        let n = 16000 * ms / 1000
        var r = Lcg(s: seed)
        var onda = [Double](repeating: 0, count: n)
        var fase = 0.0
        for i in 0..<n {
            fase += 2 * Double.pi * hz / 16000
            onda[i] = tom ? sin(fase) * 0.8 + sin(fase * 2) * 0.2 + (r.next() - 0.5) * 0.05 : r.next() * 2 - 1
        }
        let e = onda.reduce(0) { $0 + $1 * $1 }
        let atual = (e / Double(n)).squareRoot()
        let ganho = atual > 0 ? nivel / atual : 0
        var out = Data(count: n * 2)
        for i in 0..<n {
            let s = Int((max(-1, min(1, onda[i] * ganho)) * 32767).rounded())
            out[i * 2] = UInt8(s & 0xff)
            out[i * 2 + 1] = UInt8((s >> 8) & 0xff)
        }
        return out
    }

    /// Runs (level, ms) while she speaks; true if she was cut off.
    func interrompe(_ som: [(Double, Int)], tom: Bool = true) -> Bool {
        let vad = Vad(); vad.reset()
        for (nivel, ms) in som {
            var t = 0
            while t < ms {
                if vad.feed(pedaco(nivel, tom: tom), speaking: true).isBargeIn { return true }
                t += 100
            }
        }
        return false
    }

    func wav(_ nome: String) throws -> Data {
        let url = try XCTUnwrap(Bundle.module.url(forResource: nome, withExtension: "wav", subdirectory: "voice"))
        let all = try Data(contentsOf: url)
        return all.subdata(in: 44..<all.count)
    }

    func chunks(_ pcm: Data, size: Int = 2048) -> [Data] {
        var out: [Data] = []
        var i = 0
        while i < pcm.count {
            out.append(pcm.subdata(in: i..<min(i + size, pcm.count)))
            i += size
        }
        return out
    }

    func silencio(_ ms: Int = 2000) -> Data { Data(count: 16000 * 2 * ms / 1000) }

    // ------------------------------------------------------------------ barge_in_test.dart
    func testPassarinhoNaoACala() { XCTAssertFalse(interrompe([(0.0005, 500), (0.05, 300), (0.0005, 1000)], tom: false)) }
    func testDoisChilreiosTambemNao() {
        XCTAssertFalse(interrompe([(0.0005, 300), (0.05, 250), (0.0005, 400), (0.05, 250), (0.0005, 600)], tom: false))
    }
    func testTelevisaoNaSalaNaoACala() { XCTAssertFalse(interrompe([(0.035, 4000)])) }
    func testDonoAFalarCalaA() { XCTAssertTrue(interrompe([(0.0005, 200), (0.12, 900)])) }
    func testDonoComPausasEntreSilabasCalaA() {
        XCTAssertTrue(interrompe([(0.12, 300), (0.001, 100), (0.12, 300), (0.001, 100), (0.12, 300)]))
    }
    func testPausaLongaDesiste() { XCTAssertFalse(interrompe([(0.12, 100), (0.0005, 1000), (0.12, 100)])) }
    func testPalavraCurtaDeVozJaACala() { XCTAssertTrue(interrompe([(0.0005, 200), (0.12, 300)])) }
    func testAviaoNaoACala() { XCTAssertFalse(interrompe([(0.0005, 300), (0.18, 5000), (0.0005, 500)], tom: false)) }
    func testSecadorCamiaoObraNaoACalam() { XCTAssertFalse(interrompe([(0.25, 8000)], tom: false)) }
    func testShhhNaoACalaDePropositoSoVoz() { XCTAssertFalse(interrompe([(0.0005, 200), (0.18, 900)], tom: false)) }
    func testSilencioAbsolutoNuncaACala() { XCTAssertFalse(interrompe([(0.0, 5000)])) }
    func testEscreverNoTecladoNaoACala() {
        var teclas: [(Double, Int)] = []
        for _ in 0..<30 { teclas.append((0.18, 40)); teclas.append((0.0008, 160)) }
        XCTAssertFalse(interrompe(teclas, tom: false))
    }
    func testEscreverDepressaTambemNao() {
        var teclas: [(Double, Int)] = []
        for _ in 0..<40 { teclas.append((0.2, 60)); teclas.append((0.001, 60)) }
        XCTAssertFalse(interrompe(teclas, tom: false))
    }
    func testBaterNaMesaNaoACala() { XCTAssertFalse(interrompe([(0.0008, 300), (0.3, 80), (0.0008, 2000)], tom: false)) }
    func testAPropriaVozDelaNoAltifalanteNaoACala() { XCTAssertFalse(interrompe([(0.05, 8000)])) }
    func testOEcoUmPoucoMaisAltoTambemNao() { XCTAssertFalse(interrompe([(0.07, 6000)])) }
    func testComMuitoEcoEPrecisoFalarMaisAltoMasDa() {
        let vad = Vad(); vad.reset()
        var t = 0
        while t < 2000 { _ = vad.feed(pedaco(0.05), speaking: true); t += 100 }
        var cortou = false
        t = 0
        while t < 900 { if vad.feed(pedaco(0.25), speaking: true).isBargeIn { cortou = true }; t += 100 }
        XCTAssertTrue(cortou)
    }

    // ------------------------------------------------------------------ ambiente_test.dart
    func testNumCafeBarulhentoContinuaAOuvir() {
        let vad = Vad(); vad.reset()
        var t = 0
        while t < 2000 { _ = vad.feed(pedaco(0.055, tom: false, seed: 5)); t += 100 }
        var ouviu = false
        t = 0
        while t < 1500 { if vad.feed(pedaco(0.15, seed: 5)).isCapturing { ouviu = true }; t += 100 }
        XCTAssertTrue(ouviu, "ficou surda com o barulho a volta")
    }
    func testFasquiaDeOuvirNuncaPassaDoTeto() { XCTAssertLessThanOrEqual(Vad.tetoOuvir, 0.12) }
    func testChaoDeInterromperEntreEcoEVoz() {
        XCTAssertGreaterThan(Vad.bargeFloor, 0.06)
        XCTAssertLessThan(Vad.bargeFloor, 0.12)
    }

    // ------------------------------------------------------------------ silencio_test.dart
    func corre(_ ficheiro: String) throws -> (fechos: Int, falaMs: Int) {
        let vad = Vad(); vad.reset()
        var fechos = 0, falaMs = 0
        for c in chunks(try wav(ficheiro)) + chunks(silencio()) {
            let r = vad.feed(c)
            if r.isDone { fechos += 1; falaMs = r.spokeMs; vad.newTurn() }
        }
        return (fechos, falaMs)
    }
    func testFraseComPausasNaoECortadaEmPedacos() throws {
        let r = try corre("pausas")
        XCTAssertEqual(r.fechos, 1, "a frase foi partida em \(r.fechos) pedacos")
        XCTAssertGreaterThan(r.falaMs, 2000, "so apanhou \(r.falaMs) ms de fala")
    }
    func testFraseCurtaFechaUmaVez() throws {
        let r = try corre("curta")
        XCTAssertEqual(r.fechos, 1)
        XCTAssertGreaterThanOrEqual(r.falaMs, Vad.minSpeechMs)
    }
    func testSilencioDeFechoNaConstante() { XCTAssertTrue((600...900).contains(Vad.quietToCloseMs)) }

    // ------------------------------------------------------------------ vad_test.dart
    func testFraseFaladaEReconhecidaEEnviada() throws {
        let vad = Vad()
        var end: VadStep?
        for c in chunks(try wav("fala")) + chunks(silencio()) {
            let r = vad.feed(c)
            if r.isDone { end = r; break }
        }
        let e = try XCTUnwrap(end, "nunca fechou a frase")
        XCTAssertTrue(e.enough, "a frase foi descartada como too short")
        XCTAssertGreaterThan(e.spokeMs, Vad.minSpeechMs)
    }
    func testSoRuidoDeFundoNaoEEnviado() {
        let vad = Vad()
        var noise = Data(count: 2048)
        for i in stride(from: 0, to: noise.count, by: 2) { noise[i] = 12; noise[i + 1] = 0 }
        var end: VadStep?
        for _ in 0..<200 { let r = vad.feed(noise); if r.isDone { end = r; break } }
        XCTAssertFalse(end?.enough ?? false)
    }
    func testPausaCurtaNoMeioNaoFecha() throws {
        let vad = Vad()
        let fala = chunks(try wav("fala"))
        let pausa = chunks(silencio(500))
        let all = Array(fala.prefix(20)) + pausa + Array(fala.dropFirst(20))
        var closedEarly = false
        for c in all.prefix(20 + pausa.count + 5) { if vad.feed(c).isDone { closedEarly = true; break } }
        XCTAssertFalse(closedEarly, "cortava a meio da frase")
    }

    // ------------------------------------------------------------------ voz_vs_ruido_test.dart
    func tomMaximo(_ ficheiro: String) throws -> Double {
        chunks(try wav(ficheiro)).filter { Vad.rmsOf($0) > 0.02 }.map { Vad.periodicidade($0) }.max() ?? 0
    }
    func cala(_ ficheiro: String) throws -> Bool {
        let vad = Vad(); vad.reset()
        for c in chunks(try wav(ficheiro)) {
            if vad.feed(c, speaking: true).isBargeIn { return true }
        }
        return false
    }
    func testVozTemTomTecladoNao() throws {
        for v in ["para", "espera", "curta", "pausas"] {
            let t = try tomMaximo(v)
            XCTAssertGreaterThan(t, Vad.bargeVozMin, "\(v) deu tom \(t)")
        }
        let teclado = try tomMaximo("teclado")
        XCTAssertLessThan(teclado, Vad.bargeVozMin, "as teclas deram tom \(teclado)")
    }
    func testPalavraCurtaParaCalaA() throws { XCTAssertTrue(try cala("para")) }
    func testEsperaTambemACala() throws { XCTAssertTrue(try cala("espera")) }
    func testDigitarNaoACala() throws { XCTAssertFalse(try cala("teclado")) }

    // ------------------------------------------------------------------ whisper (contract)
    func testSussurroEPicoBaixoETomBaixo() {
        let vad = Vad(); vad.reset()
        for _ in 0..<3 { _ = vad.feed(pedaco(0.001)) }
        for _ in 0..<10 { _ = vad.feed(pedaco(0.06, tom: false)) }
        XCTAssertTrue(vad.foiSussurro)
        let alto = Vad(); alto.reset()
        for _ in 0..<3 { _ = alto.feed(pedaco(0.001)) }
        for _ in 0..<10 { _ = alto.feed(pedaco(0.15)) }
        XCTAssertFalse(alto.foiSussurro)
    }
}

final class VoiceApiTests: XCTestCase {
    func testReplyReadsSpeechAndWhisper() throws {
        let j = #"{"status":"replied","reply":"**Yes!** It costs 59.90. Anything else?","speech":"Yes! It costs 59.90.","whisper":true}"#
        let r = try JSONDecoder().decode(OryksaReply.self, from: Data(j.utf8))
        XCTAssertEqual(r.speech, "Yes! It costs 59.90.")
        XCTAssertTrue(r.whisper)
        let old = try JSONDecoder().decode(OryksaReply.self, from: Data(#"{"status":"replied","reply":"Hi"}"#.utf8))
        XCTAssertNil(old.speech)
        XCTAssertFalse(old.whisper)
    }

    func testAgentIdentityFromOryksa() throws {
        let j = #"{"name":"Sofia","avatar":"https://x/ai.jpg","voice":"v123","language":"pt","voice_replies":true}"#
        let a = try JSONDecoder().decode(OryksaAgent.self, from: Data(j.utf8))
        XCTAssertEqual(a.name, "Sofia")
        XCTAssertEqual(a.photo, "https://x/ai.jpg")
        XCTAssertEqual(a.voice, "v123")
        XCTAssertEqual(a.language, "pt")
        XCTAssertTrue(a.voiceReplies)
    }

    func testAppContextJson() {
        let c = OryksaAppContext(screen: "product", title: "Lavender candle", items: (0..<30).map { "item \($0)" })
        XCTAssertEqual(c.json["screen"] as? String, "product")
        XCTAssertEqual(c.json["title"] as? String, "Lavender candle")
        XCTAssertEqual((c.json["items"] as? [String])?.count, 20)
        XCTAssertTrue(OryksaAppContext().json.isEmpty)
    }
}

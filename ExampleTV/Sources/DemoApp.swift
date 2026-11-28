// ORYKSA TV SDK demo for Apple TV, a TEST app (the same as the Flutter example_tv and the Android example-tv).
//
// Without a chat token it runs on the SIMULATED backend (orange band): nothing it shows proves the ORYKSA
// server. With the PUBLIC chat token of a TEST account it uses the real server through a public session
// (never a secret key). The token comes only from the environment at run time, never from the repository:
//   ORYKSA_CHAT_TOKEN_FILE=<file with the token>   (preferred: only the path shows anywhere)
//   ORYKSA_CHAT_TOKEN=<token>
// Launch arguments: -lang <locale> (first language), -oryksaProof YES (shows the last presenter answer, for
// the UI test), -oryksaFreshCache YES (starts with no kept lines). Build, run and test steps: TVOS-SIMULADOR.md.
import Combine
import OryksaTV
import SwiftUI

@main
struct OryksaTVDemoApp: App {
    var body: some Scene {
        WindowGroup { DemoHome() }
    }
}

@MainActor
final class DemoState: ObservableObject {
    let tv: OryksaTv
    let simulated: Bool
    let mic: Bool
    let proofOverlay: Bool
    let log: DemoProofLog
    @Published private(set) var locale: String
    @Published var showAssistant = false
    @Published var showPhone = false
    @Published private(set) var lastPhone = ""
    private var bag: [AnyCancellable] = []

    /// The token of the TEST account from the environment, or nil (simulated).
    private static func chatToken(_ env: [String: String]) -> String? {
        if let f = env["ORYKSA_CHAT_TOKEN_FILE"], !f.isEmpty,
           let t = try? String(contentsOfFile: (f as NSString).expandingTildeInPath, encoding: .utf8) {
            let token = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if !token.isEmpty { return token }
        }
        let v = (env["ORYKSA_CHAT_TOKEN"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    init() {
        let env = ProcessInfo.processInfo.environment
        let defaults = UserDefaults.standard
        let token = DemoState.chatToken(env)
        let first = defaults.string(forKey: "lang").map { demoInitialLocale($0) } ?? demoInitialLocale(oryksaTvDeviceLocale())
        let proof = DemoProofLog.shared
        let inner: OryksaTvBackend
        if let t = token {
            let conversation = "tvdemo" + String(UInt64.random(in: 0...UInt64.max), radix: 16)
            inner = OryksaTvClientBackend(OryksaTv.publicClient(chatToken: t, conversationId: conversation))
        } else {
            inner = OryksaTvFakeBackend(platform: OryksaTvPlatform.tvos.wire, voice: { text, _ in DemoVoice.silence(for: text) })
        }
        // -oryksaFreshCache YES: a new folder for the kept lines of this run (the UI test starts with nothing kept;
        // nothing is deleted).
        let cacheDir: URL? = defaults.bool(forKey: "oryksaFreshCache")
            ? FileManager.default.temporaryDirectory.appendingPathComponent("oryksa_tv_voice_\(UUID().uuidString)", isDirectory: true)
            : nil
        log = proof
        simulated = token == nil
        mic = OryksaTvMic.isAvailable()
        proofOverlay = defaults.bool(forKey: "oryksaProof")
        locale = first
        tv = OryksaTv(backend: DemoLoggingBackend(inner, log: proof), locale: first, cacheDirectory: cacheDir)

        #if DEBUG
        assert(demoForbiddenHits().isEmpty, "a word of one variant in the other: \(demoForbiddenHits())")
        #endif
        // Technical labels (mode, platform, locale codes, voices) go to the log only, never on screen.
        proof.write("start mode=\(simulated ? "SIMULATED" : "REAL") platform=\(tv.backend.platform) locale=\(first) app_id=\(Bundle.main.bundleIdentifier ?? "-") mic=\(mic)")
        tv.presenter.onError = { e in proof.write("presenter error: \(e)") }
        tv.presenter.$phase.removeDuplicates().sink { p in proof.write("presenter phase=\(p)") }.store(in: &bag)
        tv.phoneVoice.texts.sink { [weak self] t in self?.lastPhone = t }.store(in: &bag)
        tv.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &bag)
        Task { _ = await tv.configOrFallback() }
    }

    func text(_ key: String) -> String { demoStrings(locale)[key] ?? key }

    /// "Hear the host": a spoken line (the same line each time: the second time the device has it).
    func hear() {
        let line = text("welcome")
        let presenter = tv.presenter
        Task { await presenter.say(line) }
    }

    /// "Subtitles only": a line with no sound, charged at the text price.
    func captionsOnly() {
        let line = text("captions_line")
        let presenter = tv.presenter
        Task { await presenter.say(line, voice: false) }
    }

    /// Changes everything at once: the screen, the server's texts and the voice.
    func nextLocale() {
        let i = ((demoLocales.firstIndex(of: locale) ?? -1) + 1) % demoLocales.count
        locale = demoLocales[i]
        tv.setLocale(locale)
        log.write("locale=\(locale)")
        let t = tv
        Task { _ = await t.configOrFallback() }
    }

    /// The phone button: the label the server gives (tv.actions phone_voice) in this language, else the demo's own.
    var phoneLabel: String {
        if let cfg = tv.currentConfig, cfg.locale == OryksaTvSimulated.resolveLocale(locale),
           let a = cfg.actions.first(where: { $0.kind == .phoneVoice }) {
            return a.label
        }
        return text("phone")
    }
}

struct DemoHome: View {
    @StateObject private var demo = DemoState()

    var body: some View {
        DemoScreen(demo: demo, tv: demo.tv, log: demo.log)
    }
}

struct DemoScreen: View {
    @ObservedObject var demo: DemoState
    @ObservedObject var tv: OryksaTv
    @ObservedObject var log: DemoProofLog

    var body: some View {
        let muted = Color(red: 0.769, green: 0.749, blue: 0.847)
        ZStack(alignment: .topLeading) {
            Color(red: 0.055, green: 0.043, blue: 0.102).ignoresSafeArea()
            VStack(alignment: .leading, spacing: 20) {
                Text(demo.text("title"))
                    .font(.system(size: 44, weight: .heavy))
                    .foregroundColor(.white)
                    .accessibilityIdentifier("demo-title")
                if demo.simulated {
                    Text(demo.text("simulated"))
                        .font(.system(size: 24, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 8)
                        .background(Color(red: 0.706, green: 0.325, blue: 0.035))
                        .accessibilityIdentifier("demo-mode")
                }
                Text("\(demo.text("language")): \(demo.text("language_name"))")
                    .font(.system(size: 28)).foregroundColor(muted)
                    .accessibilityIdentifier("demo-locale")
                Text("\(demo.text("mic")): \(demo.mic ? demo.text("mic_yes") : demo.text("mic_no"))")
                    .font(.system(size: 28)).foregroundColor(muted)
                if !demo.lastPhone.isEmpty {
                    Text("\(demo.text("phone_last")): “\(demo.lastPhone)”")
                        .font(.system(size: 28)).foregroundColor(muted)
                        .accessibilityIdentifier("demo-phone-last")
                }
                // Two rows, so every button is on screen at once (in one row the fifth was cut at the right edge at
                // 1080p, and the pt-BR labels are longer). Each row is a focus section: up and down change rows.
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 24) {
                        OryksaTvButton(demo.text("presenter"), systemImage: "person.wave.2", accessibilityID: "demo-presenter") {
                            demo.hear()
                        }
                        OryksaTvButton(demo.text("assistant"), systemImage: "bubble.left.and.bubble.right", accessibilityID: "demo-assistant") {
                            demo.showAssistant = true
                        }
                        OryksaTvButton(demo.phoneLabel, systemImage: "qrcode", accessibilityID: "demo-phone") {
                            demo.showPhone = true
                        }
                    }
                    .focusSection()
                    HStack(spacing: 24) {
                        OryksaTvButton(demo.text("change_language"), systemImage: "globe", accessibilityID: "demo-language") {
                            demo.nextLocale()
                        }
                        OryksaTvButton(demo.text("captions"), systemImage: "captions.bubble", accessibilityID: "demo-captions") {
                            demo.captionsOnly()
                        }
                    }
                    .focusSection()
                }
                .padding(24)
                .padding(.top, 20)
                if demo.proofOverlay {
                    Text(log.last)
                        .font(.system(size: 20, design: .monospaced))
                        .foregroundColor(.yellow)
                        .lineLimit(4)
                        .accessibilityIdentifier("demo-proof")
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)
        }
        .oryksaTvPresenter(tv)
        .oryksaTvAssistant(isPresented: $demo.showAssistant, tv: tv)
        .sheet(isPresented: $demo.showPhone) {
            OryksaPairingCard(tv: tv)
        }
    }
}

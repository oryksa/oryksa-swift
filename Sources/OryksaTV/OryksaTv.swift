// ORYKSA TV SDK for Apple TV: the TV pieces of one app. License: MIT. Docs: https://developer.oryksa.com
import Combine
import Foundation
import Oryksa

/// The ORYKSA TV pieces of one app: the `presenter`, the `phoneVoice` and the configuration from the
/// server. Create one and keep it while the app runs.
///
/// ```swift
/// let client = OryksaClient(getToken: { try await myServerToken() }) // sends platform "tvos" on Apple TV
/// let tv = OryksaTv(client: client, locale: "pt-BR")
/// await tv.presenter.say("Olá! Sou a ORYKSA.")
/// ```
@MainActor
public final class OryksaTv: ObservableObject {
    /// Where the pieces get their data.
    public let backend: OryksaTvBackend

    /// The language of the app screen (BCP-47), as given by the app. Change it with `setLocale(_:)`.
    @Published public private(set) var locale: String

    /// The last configuration read from the server, or nil before the first one.
    @Published public private(set) var currentConfig: OryksaTvConfig?

    /// The presenter: the AI speaks on screen with the voice of the locale and big subtitles.
    public let presenter: OryksaPresenter

    /// The phone as the microphone (QR).
    public let phoneVoice: OryksaPhoneVoice

    /// How long the configuration is kept before it is read again (10 minutes). The business may change
    /// its voice, texts or rules while the app is open; a new voice_rev then also stops the old kept
    /// lines from playing.
    var configTTL: TimeInterval = 600

    private var configTask: Task<OryksaTvConfig, Error>?
    private var configFor: String?
    private var configAt = Date.distantPast
    private var forward: [AnyCancellable] = []

    /// The TV pieces on the ORYKSA API through `client`. `locale` is the language of your app screen
    /// (BCP-47, for example `pt-BR`); by default the device's.
    public convenience init(client: OryksaClient, locale: String? = nil, audioPlayer: OryksaTvAudioPlayer? = nil,
                            cacheDirectory: URL? = nil) {
        self.init(backend: OryksaTvClientBackend(client), locale: locale, audioPlayer: audioPlayer, cacheDirectory: cacheDirectory)
    }

    /// The TV pieces on any `backend`, for example `OryksaTvFakeBackend` in tests and demos.
    /// - audioPlayer: the voice player (default `OryksaTvSystemAudioPlayer`).
    /// - cacheDirectory: the folder of the kept lines (default `Caches/oryksa_tv_voice`).
    public init(backend: OryksaTvBackend, locale: String? = nil, audioPlayer: OryksaTvAudioPlayer? = nil,
                cacheDirectory: URL? = nil) {
        self.backend = backend
        self.locale = oryksaTvNormalizeLocale(locale ?? oryksaTvDeviceLocale())
        self.presenter = OryksaPresenter(player: audioPlayer ?? OryksaTvSystemAudioPlayer(),
                                         cache: OryksaTvVoiceCache(directory: cacheDirectory))
        self.phoneVoice = OryksaPhoneVoice()
        presenter.tv = self
        phoneVoice.tv = self
        // Views that watch the TV pieces also see the presenter and the phone change.
        forward = [
            presenter.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
            phoneVoice.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() },
        ]
    }

    /// A client for an Apple TV app WITHOUT a server of its own: a public session from the business's
    /// public chat token, with `platform: tvos` and `app_id` (your bundle id). When the business limits its
    /// chat, it must list your bundle id in its allowed apps. `app_id` is a filter, not strong protection
    /// (it can be imitated): the strong protection is a token from your own server (`POST /v1/sessions`).
    /// Pass a random `conversationId` saved on the device to keep the history between launches.
    nonisolated public static func publicClient(chatToken: String, conversationId: String,
                                                customerName: String? = nil) -> OryksaClient {
        OryksaClient.public(chatToken: chatToken, conversationId: conversationId, customerName: customerName,
                            platform: OryksaTvPlatform.tvos.wire, appId: Bundle.main.bundleIdentifier)
    }

    /// Changes the language: the configuration is read again in the new one.
    public func setLocale(_ value: String) {
        let l = oryksaTvNormalizeLocale(value)
        if l == locale { return }
        locale = l
        configTask = nil
        configFor = nil
        currentConfig = nil
    }

    /// The TV configuration for `locale`, kept for 10 minutes (pass `refresh` to read it again now).
    public func config(refresh: Bool = false) async throws -> OryksaTvConfig {
        let l = locale
        let fresh = Date().timeIntervalSince(configAt) < configTTL
        if !refresh, fresh, configFor == l, let t = configTask { return try await t.value }
        configFor = l
        configAt = Date()
        let b = backend
        let t: Task<OryksaTvConfig, Error> = Task { @MainActor in try await b.config(l) }
        configTask = t
        do {
            let c = try await t.value
            if configFor == l { currentConfig = c }
            return c
        } catch {
            if configFor == l && configTask == t { configTask = nil }
            throw error
        }
    }

    /// The configuration is read again on the next use.
    func markConfigStale() { configAt = .distantPast }

    /// Like `config()`, but when the server cannot be reached returns a configuration with the English
    /// fallback texts (the pieces keep working, without the server's texts).
    public func configOrFallback() async -> OryksaTvConfig {
        do {
            return try await config()
        } catch {
            oryksaTvLog.info("ORYKSA TV: could not read the configuration (\(String(describing: error), privacy: .public)); using the fallback.")
            return OryksaTvConfig(locale: locale, presenterName: "ORYKSA", presenterAvatar: OryksaTvConfig.defaultAvatar,
                                  fromServer: false)
        }
    }

    /// Stops the presenter and ends the phone pairing. Call it when the app no longer needs the TV pieces.
    public func close() {
        presenter.stop()
        let pv = phoneVoice
        Task { await pv.stop() }
    }
}

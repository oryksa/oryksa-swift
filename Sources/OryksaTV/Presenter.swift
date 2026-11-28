// ORYKSA TV SDK: the presenter (the AI speaks on screen with the voice of the locale and big subtitles),
// her voice player and the cache of the lines she already said. License: MIT.
import AVFoundation
import CryptoKit
import Foundation
import Oryksa

// MARK: - Voice cache

/// Where the presenter keeps the lines she already said (MP3 files in the caches folder), so a repeated
/// line plays again with no new voice made. It is still charged each time: the presenter asks the server
/// for every line, with `cached: true` and its `voice_rev`, and shows it only once the server has counted
/// it. The system may empty the caches folder at any time (tvOS does it when space is short); a missing
/// file only means the voice is made again.
public struct OryksaTvVoiceCache {
    /// The folder of the files.
    public let directory: URL
    /// Most lines kept on disk; the oldest go first.
    public var maxFiles = 300

    /// The cache in `directory`, or in `Caches/oryksa_tv_voice` of the app.
    public init(directory: URL? = nil) {
        self.directory = directory ?? OryksaTvVoiceCache.defaultDirectory
    }

    /// `Caches/oryksa_tv_voice` (tvOS apps keep files in Caches).
    public static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("oryksa_tv_voice", isDirectory: true)
    }

    func file(for key: String) -> URL {
        let hex = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hex + ".mp3")
    }

    /// The kept file of `key`, or nil.
    func get(_ key: String) -> URL? {
        let f = file(for: key)
        let size = (try? f.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
        return size > 0 ? f : nil
    }

    /// Saves `mp3` under `key` and returns the file, or nil when it cannot be written.
    func put(_ key: String, _ mp3: Data) -> URL? {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let f = file(for: key)
            try mp3.write(to: f, options: .atomic)
            prune()
            return f
        } catch {
            return nil
        }
    }

    private func prune() {
        let fm = FileManager.default
        guard let all = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]) else { return }
        let mp3 = all.filter { $0.pathExtension == "mp3" }
        if mp3.count <= maxFiles { return }
        func date(_ u: URL) -> Date { (try? u.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast }
        for u in mp3.sorted(by: { date($0) < date($1) }).prefix(mp3.count - maxFiles) { try? fm.removeItem(at: u) }
    }
}

// MARK: - Audio player

/// Plays the presenter's voice. The default is `OryksaTvSystemAudioPlayer`; tests pass their own.
@MainActor
public protocol OryksaTvAudioPlayer: AnyObject {
    /// Loads an MP3 `file` (or `data` when there is no file) and returns its length in seconds when known.
    func load(file: URL?, data: Data?) async throws -> TimeInterval?
    /// Plays what was loaded. Returns when it ends or is stopped.
    func play() async throws
    /// Stops playing (a waiting `play` returns).
    func stop()
}

/// The presenter's voice with `AVAudioPlayer`, from the kept file, as media playback.
@MainActor
public final class OryksaTvSystemAudioPlayer: NSObject, OryksaTvAudioPlayer, AVAudioPlayerDelegate {
    private var player: AVAudioPlayer?
    private var done: CheckedContinuation<Void, Never>?

    public func load(file: URL?, data: Data?) async throws -> TimeInterval? {
        stop()
        let bytes: Data
        if let f = file {
            bytes = try Data(contentsOf: f)
        } else if let d = data {
            bytes = d
        } else {
            return nil
        }
        let p = try AVAudioPlayer(data: bytes)
        p.delegate = self
        p.prepareToPlay()
        player = p
        return p.duration > 0 ? p.duration : nil
    }

    public func play() async throws {
        guard let p = player else { return }
        OryksaTvSystemAudioPlayer.activateSession()
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            finish()
            done = c
            p.currentTime = 0
            if !p.play() { finish() }
        }
    }

    public func stop() {
        player?.stop()
        finish()
    }

    private func finish() {
        let d = done
        done = nil
        d?.resume()
    }

    private func ended(_ id: ObjectIdentifier) {
        if let p = player, ObjectIdentifier(p) == id { finish() }
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.ended(id) }
    }

    nonisolated public func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let id = ObjectIdentifier(player)
        Task { @MainActor in self.ended(id) }
    }

    /// Media playback (the voice plays even with the silent switch on iPad; on Apple TV it is the usual output).
    static func activateSession() {
        #if os(iOS) || os(tvOS)
        let s = AVAudioSession.sharedInstance()
        try? s.setCategory(.playback, mode: .default)
        try? s.setActive(true)
        #endif
    }
}

// MARK: - Presenter

/// What the presenter is doing.
public enum OryksaPresenterPhase: Equatable, Sendable {
    /// Quiet.
    case idle
    /// Getting the voice.
    case preparing
    /// Speaking (or showing the subtitles when there is no voice).
    case speaking
}

/// The presenter: the AI speaks on screen with the voice of the locale (from the server, never in the
/// code) and big subtitles. Get it from `OryksaTv.presenter` and show it with `OryksaPresenterView`
/// (or `.oryksaTvPresenter(tv)`).
///
/// Every line she says, or only shows, is charged each time by the ORYKSA interaction cost table (per
/// piece of up to 600 characters), a repeated line too: a spoken line at the voice price, a
/// subtitles-only line at the text price. The exact number comes in the `X-ORYKSA-Interactions-Spent`
/// header, and the line appears only once the server has counted it. Lines already said are kept on
/// the device, so the server does not have to make the same voice again.
@MainActor
public final class OryksaPresenter: ObservableObject {
    /// The TV pieces.
    public internal(set) weak var tv: OryksaTv?
    private let player: OryksaTvAudioPlayer
    private let cache: OryksaTvVoiceCache

    /// Called when she starts speaking (lower your music or video).
    public var onStart: (() -> Void)?
    /// Called when she stops speaking.
    public var onEnd: (() -> Void)?
    /// Called with errors (network, no interactions left, a line the server did not count, with code
    /// `not_counted`). A line the server did not count is not shown.
    public var onError: ((Error) -> Void)?

    /// How long a subtitle stays on screen when there is no voice (tests shorten it).
    var readingTime: (String) -> TimeInterval = oryksaTvReadingTime

    /// What she is doing.
    @Published public private(set) var phase: OryksaPresenterPhase = .idle
    /// The subtitle on screen now.
    @Published public private(set) var line = ""
    /// The whole text she is saying.
    @Published public private(set) var text = ""

    /// True while she speaks or prepares to.
    public var isBusy: Bool { phase != .idle }

    private var turn = 0
    private var current: Task<Void, Never>?
    private var mem: [String: Data] = [:]
    private var memOrder: [String] = []
    /// The voice revision the server sent for each locale (`X-ORYKSA-Voice-Rev`), used for the cache when
    /// the configuration has none (servers without the `tv` block).
    private var revByLocale: [String: String] = [:]

    init(player: OryksaTvAudioPlayer, cache: OryksaTvVoiceCache) {
        self.player = player
        self.cache = cache
    }

    /// Says `text` (written by your app) in the locale of the TV pieces, with subtitles. Returns when she
    /// finishes, is stopped or is given another text. Never throws: errors go to `onError`. Each piece of
    /// the text is charged each time, even a line said before; a piece the server did not count is not
    /// shown, and she stops there.
    ///
    /// With `voice: false` she shows the subtitles only, at reading speed, without any sound (for a TV
    /// without sound, at night, or a line that should only be read), charged at the text price. OK and
    /// Back on the remote stop her as usual.
    public func say(_ text: String, whisper: Bool = false, voice: Bool = true) async {
        turn += 1
        let my = turn
        halt()
        let t = oryksaTvCollapse(text)
        if t.isEmpty {
            if isBusy { toIdle() }
            return
        }
        let wasIdle = !isBusy
        self.text = t
        line = ""
        phase = .preparing
        if wasIdle { onStart?() }
        // A statement body (not `await self?.speakAll(...)` as the last expression): the task must be
        // Task<Void, Never>, the type of `current` (Xcode 27.2: "cannot assign Task<()?, Never>").
        let task: Task<Void, Never> = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.speakAll(t, whisper: whisper, voice: voice, my: my)
        }
        current = task
        await task.value
    }

    /// Asks the AI to write a line (`instructions` and `input`, as in `client.ai`) in the locale of the TV
    /// pieces and says it. Returns the text. The AI answer and the line are both charged by the ORYKSA
    /// interaction cost table (`voice: false`: the subtitles only, at the text price).
    @discardableResult
    public func sayGenerated(instructions: String, input: String? = nil, whisper: Bool = false, voice: Bool = true) async throws -> String {
        guard let tv = tv else { return "" }
        let cfg = await tv.configOrFallback()
        let r = try await tv.backend.ai(
            instructions: "\(instructions)\n\nWrite the answer in the language of the locale \(cfg.locale), "
                + "as plain text to be spoken aloud (no markdown, no lists, no emojis), "
                + "at most \(cfg.rules.presenterMaxChars) characters.",
            input: input, schema: nil)
        let said = r.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if !said.isEmpty { await say(said, whisper: whisper, voice: voice) }
        return said
    }

    /// Stops speaking now.
    public func stop() {
        turn += 1
        halt()
        if isBusy { toIdle() }
    }

    private func halt() {
        current?.cancel()
        current = nil
        player.stop()
    }

    private func toIdle() {
        phase = .idle
        line = ""
        text = ""
        onEnd?()
    }

    private func show(_ l: String) {
        line = l
        phase = .speaking
    }

    private func memPut(_ key: String, _ data: Data) {
        if mem[key] == nil { memOrder.append(key) }
        mem[key] = data
        while memOrder.count > 30 { mem.removeValue(forKey: memOrder.removeFirst()) }
    }

    private func speakAll(_ t: String, whisper: Bool, voice: Bool, my: Int) async {
        defer { if my == turn { toIdle() } }
        guard let tv = tv else { return }
        let cfg = await tv.configOrFallback()
        for chunk in oryksaTvSplitForSpeech(t, max: cfg.rules.presenterMaxChars) {
            if my != turn || Task.isCancelled { return }
            if !(await speakChunk(chunk, cfg: cfg, whisper: whisper, voice: voice, my: my, tv: tv)) { return }
        }
    }

    /// Shows `lines` one by one at reading speed, with no sound.
    private func readOnly(_ lines: [String], my: Int) async {
        for l in lines {
            if my != turn || Task.isCancelled { return }
            show(l)
            do { try await Task.sleep(nanoseconds: oryksaTvNanos(readingTime(l))) } catch { return }
        }
    }

    /// Says one piece. False when the server did not count it: then nothing is shown and she stops.
    private func speakChunk(_ chunk: String, cfg: OryksaTvConfig, whisper: Bool, voice: Bool, my: Int, tv: OryksaTv) async -> Bool {
        func key(_ rev: String?) -> String { "\(rev ?? "-")|\(cfg.locale)|\(whisper ? 1 : 0)|\(chunk)" }
        let rev0 = cfg.voiceRev ?? revByLocale[cfg.locale]
        var k = key(rev0)
        var file: URL? = nil
        var bytes: Data? = nil
        if voice {
            file = cache.get(k)
            bytes = file == nil ? mem[k] : nil
        }
        let kept = file != nil || bytes != nil
        // Every piece is asked of the server each time, even one the device already has: each time she says
        // it, it is charged (owner, 26/11/2026). For a kept line the server only charges it, with no new voice.
        let sp: OryksaTvSpeech?
        do {
            sp = try await tv.backend.speak(chunk, locale: cfg.locale, whisper: whisper, voice: voice, cachedRev: kept ? rev0 : nil)
        } catch {
            if my == turn { onError?(error) }
            return false
        }
        if my != turn { return false }
        guard let s = sp, (s.interactionsSpent ?? 0) >= 1 else {
            onError?(OryksaError(status: 0, code: "not_counted", message: "The server did not count this line, so it is not shown."))
            return false
        }
        if voice && !s.data.isEmpty {
            if let rev = s.voiceRev, !rev.isEmpty { revByLocale[cfg.locale] = rev }
            // The server speaks with another voice than the configuration says: the business changed it, so the
            // configuration is read again and the old kept lines stop being used.
            if let rev = s.voiceRev, let cr = cfg.voiceRev, rev != cr { tv.markConfigStale() }
            k = key(s.voiceRev ?? cfg.voiceRev)
            file = cache.put(k, s.data)
            bytes = nil
            if file == nil {
                bytes = s.data
                memPut(k, s.data)
            }
        }
        if my != turn { return false }
        let lines = oryksaTvSubtitleLines(chunk)
        if lines.isEmpty { return true }

        if file == nil && bytes == nil {
            // Counted, with no voice (asked for none, or none for this locale): the subtitles only, at reading
            // speed. Never a robot voice.
            await readOnly(lines, my: my)
            return true
        }

        let length: TimeInterval?
        do {
            length = try await player.load(file: file, data: bytes)
        } catch {
            onError?(error)
            await readOnly(lines, my: my)
            return true
        }
        if my != turn { return false }

        // Each subtitle line gets its share of the audio by length (or the reading time when the length of
        // the audio is not known).
        let total = lines.reduce(0) { $0 + ($1 as NSString).length }
        var offsets: [TimeInterval] = []
        var acc = 0
        var readAcc: TimeInterval = 0
        for l in lines {
            if let len = length, len > 0, total > 0 {
                offsets.append(len * Double(acc) / Double(total))
            } else {
                offsets.append(readAcc)
            }
            acc += (l as NSString).length
            readAcc += readingTime(l)
        }
        let marks = offsets
        show(lines[0])
        let ticker = Task { @MainActor [weak self] in
            var at: TimeInterval = 0
            for i in lines.indices.dropFirst() {
                let wait = marks[i] - at
                if wait > 0 {
                    do { try await Task.sleep(nanoseconds: oryksaTvNanos(wait)) } catch { return }
                }
                at = marks[i]
                guard let self = self, my == self.turn, !Task.isCancelled else { return }
                self.show(lines[i])
            }
        }
        do {
            try await player.play()
        } catch {
            onError?(error)
        }
        ticker.cancel()
        return true
    }
}

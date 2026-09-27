// ORYKSA voice conversation for iOS. License: MIT. Docs: https://developer.oryksa.com
#if os(iOS)
import AVFoundation
import Foundation

/// What the voice conversation is doing now.
public enum OryksaVoicePhase: Equatable {
    case starting, listening, hearing, thinking, speaking, muted, micError, noisy, notUnderstood
}

/// The ORYKSA voice conversation (the same behaviour as the ORYKSA app and every other ORYKSA channel):
/// the microphone stays open even while she speaks; only a human voice cuts her off and she stops on
/// the word (the text stays in the chat); the last second before the cut is kept; 700 ms of silence
/// closes a sentence, 15 s is the longest; a whisper gets a whispered, shorter answer; her voice is the
/// ElevenLabs voice chosen in ORYKSA, and if it fails she stays silent and the text is shown.
///
/// Needs `NSMicrophoneUsageDescription` in the app's Info.plist.
@MainActor
public final class OryksaVoiceController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published public private(set) var phase: OryksaVoicePhase = .starting
    /// Last thing the AI said and the customer said.
    @Published public private(set) var lastReply = ""
    @Published public private(set) var lastHeard = ""

    public let client: OryksaClient
    public var appContext: (() -> OryksaAppContext?)?
    public var onUserText: ((String) -> Void)?
    public var onReply: ((String) -> Void)?

    public let vad = Vad(sampleRate: 16000)
    private let sr = 16000
    private var preRollBytes: Int { sr * 2 }

    private let engine = AVAudioEngine()
    private let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true)!
    private var player: AVAudioPlayer?

    private var pcm = Data()
    private var beforeCut: [Data] = []
    private var beforeCutBytes = 0
    private var running = false
    private var closed = false
    private var speaking = false
    private var busy = false
    private var cutThisTurn = false
    private var whispered = false
    private var noiseInARow = 0
    private var turn = 0
    private var heardSomething = false

    public init(client: OryksaClient, appContext: (() -> OryksaAppContext?)? = nil,
                onUserText: ((String) -> Void)? = nil, onReply: ((String) -> Void)? = nil) {
        self.client = client
        self.appContext = appContext
        self.onUserText = onUserText
        self.onReply = onReply
    }

    private func set(_ p: OryksaVoicePhase) { if !closed && phase != p { phase = p } }

    /// Opens the microphone and starts listening.
    public func start() {
        guard !closed, !running, phase != .muted else { return }
        let session = AVAudioSession.sharedInstance()
        session.requestRecordPermission { [weak self] ok in
            Task { @MainActor in
                guard let self = self else { return }
                if !ok { self.set(.micError); return }
                self.startEngine()
            }
        }
    }

    private func startEngine() {
        let session = AVAudioSession.sharedInstance()
        do {
            // voiceChat = the system echo cancellation: she can hear the customer while she speaks
            // without hearing herself.
            try session.setCategory(.playAndRecord, mode: .voiceChat, options: [.defaultToSpeaker, .allowBluetooth, .duckOthers])
            try session.setActive(true)
        } catch {
            set(.micError)
            return
        }
        let input = engine.inputNode
        let inFormat = input.outputFormat(forBus: 0)
        guard inFormat.sampleRate > 0, let conv = AVAudioConverter(from: inFormat, to: outFormat) else {
            set(.micError)
            return
        }
        let fmt = outFormat
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 2048, format: inFormat) { [weak self] buffer, _ in
            guard let chunk = OryksaVoiceController.convert(buffer, conv, fmt) else { return }
            Task { @MainActor in self?.onAudio(chunk) }
        }
        do {
            engine.prepare()
            try engine.start()
        } catch {
            set(.micError)
            return
        }
        running = true
        vad.reset()
        pcm = Data()
        heardSomething = false
        set(.listening)
        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self = self, !self.closed, !self.heardSomething, self.phase != .muted else { return }
            self.set(.micError)
        }
    }

    /// Hardware format (usually 48 kHz float) to 16 kHz mono PCM16. Runs on the audio thread.
    nonisolated private static func convert(_ buffer: AVAudioPCMBuffer, _ conv: AVAudioConverter, _ fmt: AVAudioFormat) -> Data? {
        let ratio = 16000.0 / buffer.format.sampleRate
        let cap = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
        guard let out = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: cap) else { return nil }
        var fed = false
        var err: NSError?
        conv.convert(to: out, error: &err) { _, status in
            if fed { status.pointee = .noDataNow; return nil }
            fed = true
            status.pointee = .haveData
            return buffer
        }
        guard err == nil, out.frameLength > 0, let p = out.int16ChannelData else { return nil }
        return Data(bytes: p[0], count: Int(out.frameLength) * 2)
    }

    private func stopEngine() {
        guard running else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        running = false
    }

    private func onAudio(_ chunk: Data) {
        if closed || phase == .muted || chunk.count < 2 { return }
        if !heardSomething && Vad.rmsOf(chunk) > 0.0005 { heardSomething = true }

        // While she SPEAKS the engine only decides whether she was cut off.
        if speaking {
            beforeCut.append(chunk)
            beforeCutBytes += chunk.count
            while beforeCutBytes > preRollBytes && beforeCut.count > 1 { beforeCutBytes -= beforeCut.removeFirst().count }
            if vad.feed(chunk, speaking: true).isBargeIn { bargeIn() }
            return
        }

        let step = vad.feed(chunk)
        if step.isBargeIn { bargeIn(); return }
        if step.isCapturing || vad.capturing {
            pcm.append(chunk)
            if !busy { set(.hearing) }
        }
        guard step.isDone else { return }

        let raw = pcm
        pcm = Data()
        let whisper = vad.foiSussurro
        let stats = self.stats(empty: false, durMs: raw.count / 32)
        vad.newTurn()
        if step.enough && raw.count > sr / 2 {
            noiseInARow = 0
            handle(wav: OryksaVoiceController.wav(raw, sampleRate: sr), whisper: whisper, stats: stats)
        } else if step.isNoise {
            noiseInARow += 1
            if noiseInARow >= 2 { set(.noisy) }
        } else if !busy {
            set(.listening)
        }
    }

    /// The customer cut her off: stop the voice on the word, keep what he says.
    private func bargeIn() {
        turn += 1
        speaking = false
        busy = false
        player?.stop()
        vad.newTurn()
        vad.capturing = true
        pcm = Data()
        for c in beforeCut { pcm.append(c) }
        beforeCut.removeAll()
        beforeCutBytes = 0
        cutThisTurn = true
        set(.hearing)
    }

    /// Sends what was said right away (tap on the picture).
    public func sendNow() {
        guard !busy, !speaking, vad.capturing else { return }
        let raw = pcm
        let whisper = vad.foiSussurro
        let st = stats(empty: false, durMs: raw.count / 32)
        vad.newTurn()
        pcm = Data()
        if raw.count > sr / 2 { handle(wav: OryksaVoiceController.wav(raw, sampleRate: sr), whisper: whisper, stats: st) }
    }

    /// Audio numbers of this turn, in the ORYKSA ecosystem format (quality report).
    private func stats(empty: Bool, durMs: Int) -> [String: Any] {
        ["channel": "sdk_ios",
         "peak": (vad.picoDaFrase * 1000).rounded() / 1000,
         "pitch": (vad.tomDaFrase * 1000).rounded() / 1000,
         "noise": (vad.base * 1000).rounded() / 1000,
         "floor": Vad.bargeFloor,
         "cut": false,
         "whisper": vad.foiSussurro,
         "self_cut": cutThisTurn,
         "empty": empty,
         "dur_ms": durMs]
    }

    private func handle(wav: Data, whisper: Bool, stats: [String: Any]) {
        turn += 1
        let my = turn
        whispered = whisper
        busy = true
        set(.thinking)
        Task { @MainActor in
            let text = await client.transcribe(wav)
            guard !closed, my == turn else { return }
            guard let text = text, !text.isEmpty else {
                var st = stats; st["empty"] = true
                await client.voiceStats(st)
                busy = false
                set(text == nil ? .notUnderstood : .listening)
                return
            }
            lastHeard = text
            onUserText?(text)
            let r = try? await client.sendAndWaitReply(text, appContext: appContext?(), voice: true, whisper: whisper, voiceStats: stats)
            guard !closed, my == turn else { return }
            let reply = (r?.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !reply.isEmpty else { busy = false; set(.notUnderstood); return }
            lastReply = reply
            onReply?(reply)
            let speech = (r?.speech ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            await speak(speech.isEmpty ? reply : speech, my)
        }
    }

    /// Speaks `text` with the AI's voice (for example a greeting). If the voice fails she stays silent.
    public func say(_ text: String) async {
        turn += 1
        await speak(text, turn)
    }

    private var speakTurn = 0

    private func speak(_ text: String, _ my: Int) async {
        beforeCut.removeAll()
        beforeCutBytes = 0
        let mp3 = await client.tts(text, whisper: whispered)
        guard !closed, my == turn else { done(my); return }
        guard let data = mp3, !data.isEmpty, let p = try? AVAudioPlayer(data: data) else {
            done(my) // never a robot voice: silence + the text in the chat
            return
        }
        player = p
        p.delegate = self
        speakTurn = my
        speaking = true
        set(.speaking)
        p.play()
    }

    nonisolated public func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in self.done(self.speakTurn) }
    }

    private func done(_ my: Int) {
        cutThisTurn = false
        speaking = false
        busy = false
        vad.newTurn()
        guard !closed, my == turn else { return }
        set(.listening)
    }

    /// Mute: she stops talking and listening. Nothing is lost: what she said stays in the chat.
    public func toggleMute() {
        if phase == .muted {
            phase = .starting
            start()
            return
        }
        turn += 1
        speaking = false
        busy = false
        player?.stop()
        stopEngine()
        vad.newTurn()
        phase = .muted
    }

    /// Closes the microphone and the player.
    public func close() {
        closed = true
        turn += 1
        player?.stop()
        stopEngine()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// 16 kHz mono PCM16 WAV (what the server transcribes).
    public static func wav(_ pcm: Data, sampleRate: Int = 16000) -> Data {
        var h = Data()
        func u32(_ v: UInt32) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 4)) }
        func u16(_ v: UInt16) { var x = v.littleEndian; h.append(Data(bytes: &x, count: 2)) }
        h.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + pcm.count)); h.append("WAVE".data(using: .ascii)!)
        h.append("fmt ".data(using: .ascii)!); u32(16); u16(1); u16(1); u32(UInt32(sampleRate)); u32(UInt32(sampleRate * 2)); u16(2); u16(16)
        h.append("data".data(using: .ascii)!); u32(UInt32(pcm.count))
        return h + pcm
    }
}
#endif

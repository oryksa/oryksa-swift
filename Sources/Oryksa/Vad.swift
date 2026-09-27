// ORYKSA AI Employees SDK. License: MIT. Docs: https://developer.oryksa.com
import Foundation

/// What to do with the chunk that just arrived.
public struct VadStep: Equatable {
    public let isCapturing: Bool
    public let isDone: Bool
    public let isBargeIn: Bool
    public let spokeMs: Int
    /// Spoke enough to be worth sending?
    public let enough: Bool
    /// Not a voice: endless background noise. The reference silence went up.
    public let isNoise: Bool
    /// Average level of what was recorded.
    public let level: Double

    public static let idle = VadStep(isCapturing: false, isDone: false, isBargeIn: false, spokeMs: 0, enough: false, isNoise: false, level: 0)
    public static let capturing = VadStep(isCapturing: true, isDone: false, isBargeIn: false, spokeMs: 0, enough: false, isNoise: false, level: 0)
    public static let bargeIn = VadStep(isCapturing: false, isDone: false, isBargeIn: true, spokeMs: 0, enough: false, isNoise: false, level: 0)
    public static func done(spokeMs: Int, enough: Bool, isNoise: Bool = false, level: Double = 0) -> VadStep {
        VadStep(isCapturing: false, isDone: true, isBargeIn: false, spokeMs: spokeMs, enough: enough, isNoise: isNoise, level: level)
    }
}

/// The ORYKSA voice engine: decides WHEN someone started and stopped speaking, and whether a
/// sound while she speaks is a human voice that cuts her off.
///
/// Line by line port of `lib/vad.dart` of the ORYKSA app (the one engine of the whole
/// ecosystem). Every number is the same and has the same reason; do not change one without
/// running `VadTests` with new real recordings.
///
/// Input: PCM16 little-endian mono chunks at `sampleRate` (16 kHz).
public final class Vad {
    public let sampleRate: Int
    public init(sampleRate: Int = 16000) { self.sampleRate = sampleRate }

    /// Silence that closes a sentence (450 cut sentences, 900 was too slow; 700 is proven by the tests).
    public static let quietToCloseMs = 700
    /// Minimum speech worth sending. Below this it is a cough or a door.
    public static let minSpeechMs = 500
    /// Minimum recorded audio for the server to have something to hear.
    public static let minAudioMs = 700
    /// Closes the sentence after this, even if the person goes on.
    public static let maxSpeechMs = 15000
    /// VOICE time over her speech needed to silence her (two voiced slices). The pitch test does the heavy work.
    public static let bargeMs = 130
    /// A pause long enough to give up an interruption (typing is ~5 keys a second: 200 ms apart).
    public static let bargeGapMs = 130
    /// Continuous sound, without a single gap, so a loose slice does not count.
    public static let bargeRunMs = 64
    /// How periodic a sound must be to count as voice (keyboard <= 0.20, human voice 0.50 to 0.93).
    public static let bargeVozMin = 0.35
    /// How long the confidence lasts after the last voiced slice (the rest of the word counts).
    public static let vozValeMs = 300
    /// Minimum level to count as an interruption, MEASURED LIVE: her echo is 0.05, the person at the
    /// phone is 0.12 to 0.25. Fixed, never learnt from her echo (that also learns the person).
    public static let bargeFloor = 0.090
    /// Highest the LISTEN threshold can go, however noisy (without it she is deaf in a cafe).
    public static let tetoOuvir = 0.10
    /// Highest level that can be taken as the room's silence.
    public static let maxBase = 0.015
    /// Recording time without a pause after which we suspect it is noise.
    public static let noiseAfterMs = 4000
    /// Voice goes up and down much more than this between chunks; background noise does not.
    public static let flatRatio = 2.5
    /// Ceiling of the reference silence.
    public static let maxNoiseBase = 0.12

    private var corrida = 0
    private var maiorCorrida = 0
    private var vozHaMs = 99999

    /// Levels heard in the interruption attempt (for diagnosis).
    public private(set) var perfil: [Double] = []
    /// Peak and pitch of the sentence just recorded (whisper detection and quality report).
    public private(set) var picoDaFrase = 0.0
    public private(set) var tomDaFrase = 0.0
    /// A whisper: voice without vocal folds, low and almost without pitch. Contract: peak < 0.09 and pitch < 0.45.
    public var foiSussurro: Bool { picoDaFrase > 0 && picoDaFrase < 0.09 && tomDaFrase < 0.45 }
    /// Loudest sound while she spoke.
    public private(set) var maxEnquantoFala = 0.0
    /// Highest pitch measured in the interruption attempt.
    public private(set) var tomDaInterrupcao = 0.0

    public var base = 0.0
    public var frames = 0
    public var speechMs = 0
    public var quietMs = 0
    public var capturing = false

    private var sum = 0.0
    private var minL = 1.0
    private var maxL = 0.0
    private var count = 0

    @inline(__always) private static func sample(_ b: UnsafeRawBufferPointer, _ index: Int) -> Double {
        let lo = UInt16(b[index * 2])
        let hi = UInt16(b[index * 2 + 1])
        return Double(Int16(bitPattern: lo | (hi << 8)))
    }

    /// Is this a human VOICE or a noise? Voice is periodic (vocal folds at 70 to 350 Hz); a key, a
    /// clap, a door are clicks with no repetition. Normalised autocorrelation at 8 kHz (every other
    /// sample), lags 23 (350 Hz) to 114 (70 Hz).
    public static func periodicidade(_ chunk: Data) -> Double {
        let n = chunk.count / 2
        if n < 512 { return 0 }
        let m = n / 2
        var x = [Double](repeating: 0, count: m)
        var media = 0.0
        chunk.withUnsafeBytes { b in
            for i in 0..<m {
                x[i] = sample(b, i * 2) / 32768.0
                media += x[i]
            }
        }
        media /= Double(m)
        var energia = 0.0
        for i in 0..<m {
            x[i] -= media
            energia += x[i] * x[i]
        }
        if energia <= 0 { return 0 }
        let lagMin = 23, lagMax = 114
        var melhor = 0.0
        var lag = lagMin
        while lag <= lagMax && lag < m {
            var soma = 0.0
            var i = 0
            while i + lag < m {
                soma += x[i] * x[i + lag]
                i += 1
            }
            let r = soma / energia
            if r > melhor { melhor = r }
            lag += 1
        }
        return melhor
    }

    /// Level of this chunk (0 to 1).
    public static func rmsOf(_ chunk: Data) -> Double {
        let n = chunk.count / 2
        if n == 0 { return 0 }
        var s = 0.0
        chunk.withUnsafeBytes { b in
            for k in 0..<n {
                let v = sample(b, k) / 32768.0
                s += v * v
            }
        }
        return (s / Double(n)).squareRoot()
    }

    private func noise() -> VadStep {
        let nivel = count > 0 ? sum / Double(count) : base
        base = min(max(base, nivel), Vad.maxNoiseBase)
        return .done(spokeMs: speechMs, enough: false, isNoise: true, level: nivel)
    }

    /// Start from zero, forgetting the learnt silence. Only when a voice session starts.
    public func reset() {
        base = 0
        frames = 0
        newTurn()
    }

    /// Ready for the next sentence, KEEPING the learnt silence (the room does not change between sentences).
    public func newTurn() {
        corrida = 0
        maiorCorrida = 0
        vozHaMs = 99999
        picoDaFrase = 0
        tomDaFrase = 0
        tomDaInterrupcao = 0
        maxEnquantoFala = 0
        perfil.removeAll()
        speechMs = 0
        quietMs = 0
        capturing = false
        sum = 0
        minL = 1
        maxL = 0
        count = 0
    }

    /// Feeds one chunk. Returns what to do next.
    public func feed(_ chunk: Data, speaking: Bool = false) -> VadStep {
        let n = chunk.count / 2
        if n == 0 { return .idle }
        let rms = Vad.rmsOf(chunk)
        let ms = (n * 1000) / sampleRate
        frames += 1

        // First chunks: learn this place's silence, never above maxBase.
        if frames <= 3 && !speaking {
            base = base == 0 ? min(rms, Vad.maxBase) : min(base, rms)
        }
        // THE TWO THRESHOLDS, different on purpose. CUTTING: the measured floor, not the room
        // noise. LISTENING: follows the noise, WITH a ceiling (0.10).
        let speakThr = speaking ? max(base * 2.0, Vad.bargeFloor) : min(max(base * 3.2, 0.014), Vad.tetoOuvir)
        let quietThr = max(base * 1.8, 0.008)

        // Room noise: goes down fast, up slowly, never learns from a voice-level sound.
        if !capturing && !speaking {
            if rms < base {
                base = base * 0.8 + rms * 0.2
            } else if rms < speakThr {
                base = base * 0.98 + rms * 0.02
            }
        }

        if speaking {
            let thr = speakThr
            if perfil.count < 40 { perfil.append(rms) }
            // Only VOICE interrupts. A key click is loud but has no pitch.
            let alto = rms > thr
            if rms > maxEnquantoFala { maxEnquantoFala = rms }
            let tom = alto ? Vad.periodicidade(chunk) : 0.0
            if tom > tomDaInterrupcao { tomDaInterrupcao = tom }
            if tom >= Vad.bargeVozMin { vozHaMs = 0 } else { vozHaMs += ms }
            let ehVoz = alto && vozHaMs <= Vad.vozValeMs
            if ehVoz {
                speechMs += ms
                quietMs = 0
                corrida += ms
                if corrida > maiorCorrida { maiorCorrida = corrida }
                if speechMs >= Vad.bargeMs && maiorCorrida >= Vad.bargeRunMs { return .bargeIn }
            } else {
                corrida = 0
                quietMs += ms
                if quietMs > Vad.bargeGapMs {
                    speechMs = 0
                    quietMs = 0
                    maiorCorrida = 0
                }
            }
            return .idle
        }

        if rms > speakThr {
            capturing = true
            speechMs += ms
            quietMs = 0
            if rms > picoDaFrase { picoDaFrase = rms }
            let tf = Vad.periodicidade(chunk)
            if tf > tomDaFrase { tomDaFrase = tf }
        } else if capturing {
            if rms < quietThr { quietMs += ms }
        }
        if capturing {
            sum += rms
            if rms < minL { minL = rms }
            if rms > maxL { maxL = rms }
            count += 1
        }

        if !capturing { return .idle }

        // Background noise caught early: seconds without a pause AND always at the same level.
        let plano = minL > 0 && maxL < minL * Vad.flatRatio
        if speechMs > Vad.noiseAfterMs && quietMs == 0 && plano { return noise() }

        if quietMs <= Vad.quietToCloseMs && speechMs <= Vad.maxSpeechMs { return .capturing }

        let spoke = speechMs
        let nivel = count > 0 ? sum / Double(count) : 0.0

        // Fifteen seconds without ONE pause is not a person: it is constant noise.
        if spoke > Vad.maxSpeechMs && quietMs < 200 { return noise() }

        return .done(spokeMs: spoke, enough: spoke >= Vad.minSpeechMs, level: nivel)
    }
}

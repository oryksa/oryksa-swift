// ORYKSA TV SDK: the phone as the microphone (QR), and the TV's own microphone. License: MIT.
import Combine
import Foundation
import Oryksa
#if os(iOS)
import AVFoundation
#endif

/// Where the phone voice is.
public enum OryksaPhoneVoiceState: Equatable, Sendable {
    /// Not started.
    case idle
    /// Asking the server for a code.
    case creating
    /// The QR is on screen, waiting for the phone.
    case waiting
    /// The phone is connected.
    case paired
    /// The person is speaking on the phone.
    case listening
    /// The phone closed the page (start again for a new code).
    case phoneLeft
    /// The code expired before the phone connected (start again for a new code).
    case expired
    /// The pairing ended.
    case closed
    /// The server could not be reached (`OryksaPhoneVoice.lastError`).
    case error
}

/// The phone as the microphone: the TV shows a QR, the phone opens the ORYKSA page and what the person
/// says arrives here as text (`texts`, `onText`). Apple TV gives no microphone to apps, so this is how
/// people talk to the AI on it. Get it from `OryksaTv.phoneVoice` and show it with `OryksaPairingCard`.
@MainActor
public final class OryksaPhoneVoice: ObservableObject {
    /// The TV pieces.
    public internal(set) weak var tv: OryksaTv?

    /// Seconds each events request waits on the server (long-poll).
    var pollWait: TimeInterval = 25
    /// Pause before asking again after a network error.
    var retryPause: TimeInterval = 2

    /// Called with each text the person said on the phone.
    public var onText: ((String) -> Void)?

    private let subject = PassthroughSubject<String, Never>()

    /// Each text the person said on the phone.
    public var texts: AnyPublisher<String, Never> { subject.eraseToAnyPublisher() }

    /// Where it is.
    @Published public private(set) var state: OryksaPhoneVoiceState = .idle
    /// The pairing on screen (QR and code), or nil.
    @Published public private(set) var pairing: OryksaPairing?
    /// The last error, when `state` is `.error`.
    @Published public private(set) var lastError: Error?
    /// The last text heard.
    @Published public private(set) var lastText = ""

    private var gen = 0
    private var poller: Task<Void, Never>?
    private var expiry: Task<Void, Never>?

    init() {}

    /// True from `start()` until `stop()` (or the code expired or the pairing ended).
    public var isActive: Bool {
        switch state {
        case .creating, .waiting, .paired, .listening, .phoneLeft: return true
        case .idle, .expired, .closed, .error: return false
        }
    }

    private func set(_ s: OryksaPhoneVoiceState) {
        if state != s { state = s }
    }

    /// Asks the server for a code and waits for the phone. Does nothing while already active.
    public func start() async {
        guard !isActive, let tv = tv else { return }
        gen += 1
        let my = gen
        lastError = nil
        set(.creating)
        let p: OryksaPairing
        do {
            p = try await tv.backend.pair(tv.locale)
        } catch {
            if my != gen { return }
            lastError = error
            set(.error)
            return
        }
        if my != gen {
            await unpair(p.pairId)
            return
        }
        pairing = p
        set(.waiting)
        expiry?.cancel()
        let left = p.expiresAt.timeIntervalSinceNow
        expiry = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: oryksaTvNanos(left)) } catch { return }
            guard let self = self, my == self.gen, self.state == .waiting else { return }
            self.end(.expired)
        }
        // A statement body, as in the presenter: the task is Task<Void, Never> without relying on the type of
        // `poller` to turn `()?` into Void.
        poller = Task { @MainActor [weak self] in
            guard let self = self else { return }
            await self.poll(my, p)
        }
    }

    /// Ends the pairing (the phone page stops sending).
    public func stop() async {
        gen += 1
        expiry?.cancel()
        expiry = nil
        poller?.cancel()
        poller = nil
        let p = pairing
        pairing = nil
        set(.idle)
        if let p = p { await unpair(p.pairId) }
    }

    /// A new code: ends the current pairing and starts another.
    public func restart() async {
        await stop()
        await start()
    }

    private func unpair(_ id: String) async {
        guard let tv = tv else { return }
        try? await tv.backend.unpair(id)
    }

    private func end(_ s: OryksaPhoneVoiceState) {
        gen += 1
        expiry?.cancel()
        set(s)
    }

    private func pause() async {
        try? await Task.sleep(nanoseconds: oryksaTvNanos(retryPause))
    }

    private func poll(_ my: Int, _ p: OryksaPairing) async {
        var after = 0
        while my == gen && !Task.isCancelled {
            guard let tv = tv else { return }
            let page: OryksaPhoneEventsPage
            do {
                page = try await tv.backend.phoneEvents(p.pairId, after: after, wait: pollWait)
            } catch let e as OryksaError {
                if my != gen { return }
                if e.code == "pair_expired" || e.status == 410 { end(.expired); return }
                if e.code == "pair_not_found" || e.status == 404 { end(.closed); return }
                await pause()
                continue
            } catch {
                if my != gen { return }
                await pause()
                continue
            }
            if my != gen { return }
            after = page.next
            for e in page.events {
                if my != gen { return }
                handle(e)
            }
            if my != gen { return }
            if page.state == "expired" { end(.expired); return }
            if page.state == "closed" { end(.closed); return }
        }
    }

    private func handle(_ e: OryksaPhoneEvent) {
        switch e.type {
        case .paired:
            expiry?.cancel()
            set(.paired)
        case .listening:
            set(.listening)
        case .stopped:
            set(.paired)
        case .text:
            set(.paired)
            let t = (e.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty && e.isFinal {
                lastText = t
                onText?(t)
                subject.send(t)
            }
        case .phoneLeft:
            set(.phoneLeft)
        case .expired:
            end(.expired)
        case .closed:
            end(.closed)
        case .unknown:
            break
        }
    }
}

/// The TV's own microphone.
public enum OryksaTvMic {
    /// True when the device gives the app a microphone. It never asks for the permission. On Apple TV it
    /// is always false: the SDK opens no microphone there, so your app offers the phone (QR) instead.
    public static func isAvailable() -> Bool {
        #if os(iOS)
        return AVAudioSession.sharedInstance().isInputAvailable
        #else
        return false
        #endif
    }
}

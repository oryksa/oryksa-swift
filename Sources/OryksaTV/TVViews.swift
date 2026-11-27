// ORYKSA TV SDK: the generic pieces on screen, for the remote (tvOS focus engine). Native SwiftUI, no
// web view. Texts, names, photos and rules come from the ORYKSA server. License: MIT.
import Foundation
import Oryksa
import SwiftUI
#if os(tvOS)
import UIKit
#endif

// MARK: - Theme and sizes

/// Colours of the TV pieces. Pass your app's colours; the sizes and the focus ring stay big.
public struct OryksaTvTheme {
    /// Background of the panel.
    public var background: Color
    /// Background of buttons and cards.
    public var surface: Color
    /// Main text.
    public var text: Color
    /// Secondary text.
    public var muted: Color
    /// Focused button and highlights.
    public var accent: Color
    /// Ring around the focused item.
    public var focus: Color
    /// Box behind the subtitles.
    public var subtitleBackground: Color

    public init(background: Color = Color(red: 0.055, green: 0.043, blue: 0.102),
                surface: Color = Color(red: 0.133, green: 0.110, blue: 0.220),
                text: Color = .white,
                muted: Color = Color(red: 0.769, green: 0.749, blue: 0.847),
                accent: Color = Color(red: 0.431, green: 0.294, blue: 1.0),
                focus: Color = .white,
                subtitleBackground: Color = Color.black.opacity(0.85)) {
        self.background = background; self.surface = surface; self.text = text; self.muted = muted
        self.accent = accent; self.focus = focus; self.subtitleBackground = subtitleBackground
    }
}

/// Sizes for a TV screen: given in pixels of a 1080p screen and scaled to the real one. On Apple TV the
/// screen is 1920 x 1080 points, so one unit is one point.
public struct OryksaTvMetrics: Equatable, Sendable {
    /// Points per 1080p pixel.
    public let unit: CGFloat

    public init(unit: CGFloat = 1) { self.unit = unit }

    /// Metrics for a screen (or panel) of `size`.
    public static func of(_ size: CGSize) -> OryksaTvMetrics {
        let h = min(size.height, size.width * 9 / 16)
        return OryksaTvMetrics(unit: h <= 0 ? 1 : h / 1080)
    }

    /// `v` pixels of a 1080p screen in points.
    public func px(_ v: CGFloat) -> CGFloat { v * unit }
    /// Body text (28 px at 1080p).
    public var text: CGFloat { px(28) }
    /// Small text (24 px at 1080p).
    public var small: CGFloat { px(24) }
    /// Titles (44 px at 1080p).
    public var title: CGFloat { px(44) }
    /// Subtitles of the presenter (40 px at 1080p).
    public var subtitle: CGFloat { px(40) }
    /// Width of the focus ring.
    public var focusWidth: CGFloat { px(5) }
}

private struct OryksaTvMetricsKey: EnvironmentKey {
    static let defaultValue = OryksaTvMetrics()
}

public extension EnvironmentValues {
    /// The sizes of the TV pieces (set by the full-screen pieces for their content).
    var oryksaTvMetrics: OryksaTvMetrics {
        get { self[OryksaTvMetricsKey.self] }
        set { self[OryksaTvMetricsKey.self] = newValue }
    }
}

// MARK: - Button

/// A button for the TV remote: OK presses it, the arrows move to it, and when it has the focus it grows,
/// fills with the accent colour and gets a thick ring.
public struct OryksaTvButton: View {
    private let label: String
    private let systemImage: String?
    private let theme: OryksaTvTheme
    private let accessibilityID: String
    private let action: () -> Void
    @Environment(\.oryksaTvMetrics) private var m

    /// - systemImage: an SF Symbol before the text.
    /// - accessibilityID: the accessibility identifier (for UI tests).
    public init(_ label: String, systemImage: String? = nil, theme: OryksaTvTheme = OryksaTvTheme(),
                accessibilityID: String = "", action: @escaping () -> Void) {
        self.label = label; self.systemImage = systemImage; self.theme = theme
        self.accessibilityID = accessibilityID; self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: m.px(12)) {
                if let s = systemImage {
                    Image(systemName: s).font(.system(size: m.text * 1.05, weight: .semibold))
                }
                Text(label).lineLimit(2).multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(OryksaTvButtonStyle(theme: theme, m: m))
        .accessibilityLabel(label)
        .accessibilityIdentifier(accessibilityID)
    }
}

/// The look of `OryksaTvButton`. It draws its own focus: on tvOS a custom style replaces the system one.
struct OryksaTvButtonStyle: ButtonStyle {
    let theme: OryksaTvTheme
    let m: OryksaTvMetrics

    func makeBody(configuration: Configuration) -> some View {
        OryksaTvButtonFace(configuration: configuration, theme: theme, m: m)
    }
}

private struct OryksaTvButtonFace: View {
    let configuration: ButtonStyleConfiguration
    let theme: OryksaTvTheme
    let m: OryksaTvMetrics
    /// The focus of the button around this face.
    @Environment(\.isFocused) private var focused

    init(configuration: ButtonStyleConfiguration, theme: OryksaTvTheme, m: OryksaTvMetrics) {
        self.configuration = configuration; self.theme = theme; self.m = m
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: m.px(16), style: .continuous)
        configuration.label
            .font(.system(size: m.text, weight: focused ? .bold : .medium))
            .foregroundColor(theme.text)
            .padding(.horizontal, m.px(32))
            .padding(.vertical, m.px(16))
            .background(shape.fill(focused ? theme.accent : theme.surface))
            .overlay(shape.stroke(focused ? theme.focus : Color.clear, lineWidth: m.focusWidth))
            .shadow(color: focused ? theme.accent.opacity(0.6) : Color.clear, radius: m.px(14))
            .scaleEffect(focused ? 1.08 : (configuration.isPressed ? 0.97 : 1))
            .animation(.easeOut(duration: 0.12), value: focused)
    }
}

// MARK: - Avatar

/// Round photo of the AI, with a ring while she speaks.
public struct OryksaTvAvatar: View {
    private let url: String
    private let size: CGFloat
    private let speaking: Bool
    private let theme: OryksaTvTheme

    public init(url: String, size: CGFloat, speaking: Bool = false, theme: OryksaTvTheme = OryksaTvTheme()) {
        self.url = url; self.size = size; self.speaking = speaking; self.theme = theme
    }

    public var body: some View {
        AsyncImage(url: URL(string: url)) { phase in
            if let img = phase.image {
                img.resizable().scaledToFill()
            } else {
                theme.surface
            }
        }
        .frame(width: size * 0.9, height: size * 0.9)
        .clipShape(Circle())
        .padding(size * 0.05)
        .background(Circle().fill(speaking ? theme.accent : theme.surface))
        .shadow(color: speaking ? theme.accent.opacity(0.7) : Color.clear, radius: size * 0.15)
        .animation(.easeOut(duration: 0.2), value: speaking)
        .accessibilityHidden(true)
    }
}

// MARK: - Presenter on screen

/// The presenter on screen: her photo and name, and the subtitles in big letters, at the bottom. Place
/// it over your screen (`.oryksaTvPresenter(tv)`, or in a `ZStack`). It hides itself when she is quiet
/// unless `showWhenIdle`.
///
/// With `remoteSkips`, while she speaks OK, Play/Pause and Back on the remote stop her (and are not
/// passed to your app, so the focused button is not pressed).
@MainActor
public struct OryksaPresenterView: View {
    @ObservedObject private var tv: OryksaTv
    private let theme: OryksaTvTheme
    private let remoteSkips: Bool
    private let showWhenIdle: Bool

    public init(tv: OryksaTv, theme: OryksaTvTheme = OryksaTvTheme(), remoteSkips: Bool = true, showWhenIdle: Bool = false) {
        self.tv = tv; self.theme = theme; self.remoteSkips = remoteSkips; self.showWhenIdle = showWhenIdle
    }

    public var body: some View {
        let p = tv.presenter
        let cfg = tv.currentConfig
        GeometryReader { geo in
            let m = OryksaTvMetrics.of(geo.size)
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if p.isBusy || showWhenIdle {
                    HStack(alignment: .bottom, spacing: m.px(28)) {
                        OryksaTvAvatar(url: cfg?.presenterAvatar ?? OryksaTvConfig.defaultAvatar, size: m.px(140),
                                       speaking: p.phase == .speaking, theme: theme)
                        VStack(alignment: .leading, spacing: m.px(8)) {
                            Text(cfg?.presenterName ?? "ORYKSA")
                                .font(.system(size: m.small, weight: .heavy))
                                .kerning(1)
                                .foregroundColor(theme.accent)
                            Text(p.line)
                                .font(.system(size: m.subtitle, weight: .semibold))
                                .foregroundColor(theme.text)
                                .lineLimit(2)
                                .lineSpacing(m.px(6))
                                .accessibilityIdentifier("oryksa-tv-subtitle")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, m.px(36))
                        .padding(.vertical, m.px(24))
                        .background(RoundedRectangle(cornerRadius: m.px(20), style: .continuous).fill(theme.subtitleBackground))
                    }
                    .padding(m.px(20))
                    .transition(.opacity)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .allowsHitTesting(false)
        .animation(.easeOut(duration: 0.2), value: p.isBusy)
        .oryksaTvRemoteStops(p, enabled: remoteSkips && p.isBusy)
        .task { _ = await tv.configOrFallback() }
    }
}

public extension View {
    /// The presenter over this view: her photo, her name and big subtitles at the bottom while she
    /// speaks. OK, Play/Pause and Back stop her (see `OryksaPresenterView`).
    @MainActor
    func oryksaTvPresenter(_ tv: OryksaTv, theme: OryksaTvTheme = OryksaTvTheme(), remoteSkips: Bool = true) -> some View {
        overlay(OryksaPresenterView(tv: tv, theme: theme, remoteSkips: remoteSkips))
    }
}

extension View {
    /// While `enabled`, the OK, Play/Pause and Back keys of the remote stop `presenter` and are not
    /// passed on (tvOS only).
    @MainActor
    func oryksaTvRemoteStops(_ presenter: OryksaPresenter, enabled: Bool) -> some View {
        #if os(tvOS)
        return background(OryksaRemoteStopper(presenter: presenter, enabled: enabled).frame(width: 0, height: 0))
        #else
        return self
        #endif
    }
}

#if os(tvOS)
/// Catches the remote's OK, Play/Pause and Back while the presenter speaks. The recognizers sit on the
/// window, so they get the keys whatever has the focus; they start at the key press, so the focused
/// button (or your app's Back) never sees that key.
struct OryksaRemoteStopper: UIViewRepresentable {
    let presenter: OryksaPresenter
    let enabled: Bool

    func makeUIView(context: Context) -> OryksaRemoteStopperView { OryksaRemoteStopperView() }

    func updateUIView(_ view: OryksaRemoteStopperView, context: Context) {
        view.presenter = presenter
        view.setStopping(enabled)
    }
}

final class OryksaRemoteStopperView: UIView {
    weak var presenter: OryksaPresenter?
    private var recognizers: [UIGestureRecognizer] = []
    private var stopping = false

    func setStopping(_ on: Bool) {
        stopping = on
        for r in recognizers { r.isEnabled = on }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil { detach() }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        attach()
    }

    private func attach() {
        detach()
        guard let w = window else { return }
        for type in [UIPress.PressType.select, UIPress.PressType.playPause, UIPress.PressType.menu] {
            let r = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            r.minimumPressDuration = 0
            r.allowedPressTypes = [NSNumber(value: type.rawValue)]
            r.allowedTouchTypes = []
            r.cancelsTouchesInView = true
            r.isEnabled = stopping
            w.addGestureRecognizer(r)
            recognizers.append(r)
        }
    }

    private func detach() {
        for r in recognizers { r.view?.removeGestureRecognizer(r) }
        recognizers.removeAll()
    }

    @objc private func pressed(_ r: UILongPressGestureRecognizer) {
        guard r.state == .began else { return }
        presenter?.stop()
    }
}
#endif

// MARK: - Pairing card (phone voice)

/// The QR to talk on the phone: the code, the short address and where it stands (waiting, connected,
/// listening, expired). Starts `tv.phoneVoice` when it appears (unless `autoStart` is false). The phone
/// page is from ORYKSA; the TV never needs a microphone. The QR picture comes from the server.
@MainActor
public struct OryksaPairingCard: View {
    @ObservedObject private var tv: OryksaTv
    private let autoStart: Bool
    private let theme: OryksaTvTheme
    @Environment(\.oryksaTvMetrics) private var m
    @FocusState private var retryFocused: Bool

    public init(tv: OryksaTv, autoStart: Bool = true, theme: OryksaTvTheme = OryksaTvTheme()) {
        self.tv = tv; self.autoStart = autoStart; self.theme = theme
    }

    private func status(_ st: OryksaPhoneVoiceState, _ t: OryksaTvTexts) -> String {
        switch st {
        case .idle, .creating, .waiting: return t.get("pair_waiting")
        case .paired: return t.get("pair_connected")
        case .listening: return t.get("listening")
        case .phoneLeft: return t.get("phone_left")
        case .expired: return t.get("pair_expired")
        case .closed, .error: return t.get("error")
        }
    }

    private func codeText(_ code: String) -> some View {
        Text(code)
            .font(.system(size: m.title, weight: .heavy))
            .foregroundColor(.black)
            .accessibilityIdentifier("oryksa-tv-qr-placeholder")
    }

    public var body: some View {
        let pv = tv.phoneVoice
        let t = tv.currentConfig?.texts ?? OryksaTvTexts()
        let st = pv.state
        let ended = st == .expired || st == .closed || st == .error || st == .phoneLeft
        let p = pv.pairing
        let showQr = p != nil && !ended && st != .paired && st != .listening
        HStack(alignment: .center, spacing: m.px(36)) {
            if showQr, let p = p {
                ZStack {
                    Color.white
                    if p.qrPngUrl.isEmpty {
                        codeText(p.code)
                    } else {
                        AsyncImage(url: URL(string: p.qrPngUrl)) { phase in
                            if let img = phase.image {
                                img.interpolation(.none).resizable().scaledToFit()
                            } else if phase.error != nil {
                                codeText(p.code)
                            } else {
                                ProgressView()
                            }
                        }
                        .padding(m.px(16))
                        .accessibilityIdentifier("oryksa-tv-qr")
                    }
                }
                .frame(width: m.px(300), height: m.px(300))
            }
            VStack(alignment: .leading, spacing: m.px(12)) {
                Text(t.get("pair_title"))
                    .font(.system(size: m.title, weight: .heavy))
                    .foregroundColor(theme.text)
                if showQr, let p = p {
                    Text(t.get("pair_step_scan")).font(.system(size: m.text)).foregroundColor(theme.muted)
                    Text(t.get("pair_step_code", ["url": p.shortUrl, "code": p.code]))
                        .font(.system(size: m.text)).foregroundColor(theme.muted)
                    Text(p.code)
                        .font(.system(size: m.px(64), weight: .heavy))
                        .kerning(m.px(10))
                        .foregroundColor(theme.text)
                        .accessibilityIdentifier("oryksa-tv-pair-code")
                }
                Text(status(st, t))
                    .font(.system(size: m.text, weight: .bold))
                    .foregroundColor(theme.accent)
                    .accessibilityIdentifier("oryksa-tv-pair-status")
                if !pv.lastText.isEmpty && !ended {
                    Text("“\(pv.lastText)”")
                        .font(.system(size: m.text))
                        .foregroundColor(theme.text)
                        .lineLimit(2)
                }
                if ended {
                    OryksaTvButton(t.get("retry"), systemImage: "arrow.clockwise", theme: theme,
                                   accessibilityID: "oryksa-tv-pair-retry") {
                        Task { await pv.restart() }
                    }
                    .focused($retryFocused)
                    .padding(.top, m.px(12))
                }
            }
        }
        .padding(m.px(32))
        .background(RoundedRectangle(cornerRadius: m.px(24), style: .continuous).fill(theme.surface))
        .onChange(of: ended) { e in
            // The Retry button takes the focus once it is on screen.
            if e {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 100_000_000)
                    retryFocused = true
                }
            }
        }
        .task {
            _ = await tv.configOrFallback()
            if autoStart && !tv.phoneVoice.isActive { await tv.phoneVoice.start() }
        }
    }
}

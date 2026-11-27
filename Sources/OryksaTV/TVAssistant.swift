// ORYKSA TV SDK: the assistant panel, a conversation with the AI driven only by the remote. License: MIT.
import Combine
import Foundation
import Oryksa
import SwiftUI

/// The conversation of one open assistant panel.
@MainActor
final class OryksaTvAssistantModel: ObservableObject {
    struct Msg: Identifiable, Equatable {
        let id: Int
        let mine: Bool
        let text: String
    }

    let tv: OryksaTv
    let appContext: (() -> OryksaAppContext?)?
    @Published private(set) var msgs: [Msg] = []
    @Published private(set) var busy = false
    @Published var showPairing = false
    @Published private(set) var cfg: OryksaTvConfig?
    /// True once the presenter read a reply of this panel (closing the panel then stops her).
    private(set) var spoke = false
    private var queue: [String] = []
    private var nextId = 0
    private var bag: [AnyCancellable] = []

    init(tv: OryksaTv, appContext: (() -> OryksaAppContext?)?) {
        self.tv = tv
        self.appContext = appContext
        // What the person says on the phone goes in as a message.
        tv.phoneVoice.texts.sink { [weak self] t in
            guard let self = self else { return }
            Task { @MainActor in await self.send(t) }
        }.store(in: &bag)
    }

    func load() async {
        cfg = await tv.configOrFallback()
    }

    private func add(_ mine: Bool, _ text: String) {
        nextId += 1
        msgs.append(Msg(id: nextId, mine: mine, text: text))
    }

    /// Sends `text` to the AI; while a reply is on its way, the next ones wait in order.
    func send(_ text: String) async {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return }
        if busy {
            queue.append(t)
            return
        }
        add(true, t)
        busy = true
        let c = await tv.configOrFallback()
        let speak = c.rules.speakReplies
        var reply = ""
        var speech: String?
        var ok = false
        do {
            let r = try await tv.backend.chat(t, locale: tv.locale, appContext: appContext?(), voice: speak)
            reply = (r.reply ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            speech = r.speech?.trimmingCharacters(in: .whitespacesAndNewlines)
            ok = !reply.isEmpty
        } catch {}
        add(false, ok ? reply : c.texts.get("error"))
        busy = false
        if ok && speak {
            spoke = true
            let line = (speech?.isEmpty == false) ? (speech ?? reply) : reply
            let presenter = tv.presenter
            Task { @MainActor in await presenter.say(line) }
        }
        if !queue.isEmpty {
            let next = queue.removeFirst()
            Task { @MainActor in await self.send(next) }
        }
    }
}

/// The assistant panel: a conversation with the AI driven only by the remote (arrows, OK, Back). The
/// questions and buttons come from the server; the person can also talk on the phone (QR) or type with
/// the system keyboard (only the Send button sends). Replies are read by the presenter when the server
/// allows it. Up and down move through the messages and the buttons, left and right between the buttons.
///
/// Use `.oryksaTvAssistant(isPresented:tv:)`, or place it in your layout and close it in `onClose`.
@MainActor
public struct OryksaTvAssistant: View {
    @ObservedObject private var tv: OryksaTv
    @StateObject private var model: OryksaTvAssistantModel
    private let sidePanel: Bool
    private let theme: OryksaTvTheme
    private let onClose: () -> Void
    @State private var typing = false
    @FocusState private var focus: String?

    /// - appContext: the screen the person is on in your app (sent with each message).
    /// - sidePanel: a panel on the right instead of the whole screen.
    /// - onClose: called by Back and by the close button.
    public init(tv: OryksaTv, appContext: (() -> OryksaAppContext?)? = nil, sidePanel: Bool = false,
                theme: OryksaTvTheme = OryksaTvTheme(), onClose: @escaping () -> Void) {
        self.tv = tv
        _model = StateObject(wrappedValue: OryksaTvAssistantModel(tv: tv, appContext: appContext))
        self.sidePanel = sidePanel
        self.theme = theme
        self.onClose = onClose
    }

    private struct Item: Identifiable {
        let id: String
        let label: String
        let icon: String?
        let run: () -> Void
    }

    private var config: OryksaTvConfig? { tv.currentConfig ?? model.cfg }
    private var texts: OryksaTvTexts { config?.texts ?? OryksaTvTexts() }

    private func close() {
        if model.spoke && tv.presenter.isBusy { tv.presenter.stop() }
        onClose()
    }

    private func items() -> [Item] {
        // The buttons wait for the configuration, so the first question gets the focus.
        guard let cfg = config else { return [] }
        let t = cfg.texts
        var out: [Item] = []
        for (i, s) in cfg.suggestions.enumerated() {
            out.append(Item(id: "oryksa-tv-suggestion-\(i)", label: s, icon: nil) { Task { await model.send(s) } })
        }
        for a in cfg.actions {
            if a.kind == .phoneVoice && !cfg.rules.phoneVoice { continue }
            out.append(Item(id: "oryksa-tv-action-\(a.id)", label: a.label, icon: a.kind == .phoneVoice ? "iphone" : nil) {
                switch a.kind {
                case .message: Task { await model.send(a.message ?? a.label) }
                case .phoneVoice: model.showPairing.toggle()
                case .close: close()
                }
            })
        }
        out.append(Item(id: "oryksa-tv-type", label: t.get("type_message"), icon: "keyboard") { typing = true })
        out.append(Item(id: "oryksa-tv-close", label: t.get("close"), icon: "xmark") { close() })
        return out
    }

    private func phoneStatus(_ t: OryksaTvTexts) -> String? {
        switch tv.phoneVoice.state {
        case .paired: return t.get("pair_connected")
        case .listening: return t.get("listening")
        case .phoneLeft: return t.get("phone_left")
        default: return nil
        }
    }

    public var body: some View {
        GeometryReader { geo in
            let m = OryksaTvMetrics.of(geo.size)
            let width = sidePanel ? max(geo.size.width * 0.42, m.px(700)) : geo.size.width
            HStack(spacing: 0) {
                if sidePanel { Spacer(minLength: 0) }
                panel(m, width: width)
                    .frame(width: width)
                    .frame(maxHeight: .infinity)
                    .background(theme.background.ignoresSafeArea())
            }
            .environment(\.oryksaTvMetrics, m)
        }
        .background((sidePanel ? Color.black.opacity(0.55) : theme.background).ignoresSafeArea())
        .oryksaTvRemoteStops(tv.presenter, enabled: tv.presenter.isBusy)
        #if os(tvOS) || os(macOS)
        .onExitCommand { close() }
        #endif
        .sheet(isPresented: $typing) {
            OryksaTvTypeSheet(texts: texts, theme: theme, onSend: { text in
                typing = false
                Task { await model.send(text) }
            }, onCancel: { typing = false })
        }
        .onDisappear {
            if model.spoke && tv.presenter.isBusy { tv.presenter.stop() }
        }
        .task {
            await model.load()
            // The first button takes the focus once the server's buttons are on screen.
            try? await Task.sleep(nanoseconds: 150_000_000)
            if focus == nil { focus = items().first?.id }
        }
    }

    private func panel(_ m: OryksaTvMetrics, width: CGFloat) -> some View {
        let cfg = config
        let t = texts
        let status = model.showPairing ? nil : phoneStatus(t)
        let buttons = items()
        return VStack(alignment: .leading, spacing: m.px(20)) {
            HStack(spacing: m.px(24)) {
                OryksaTvAvatar(url: cfg?.presenterAvatar ?? OryksaTvConfig.defaultAvatar, size: m.px(96),
                               speaking: tv.presenter.isBusy, theme: theme)
                VStack(alignment: .leading, spacing: m.px(6)) {
                    Text(t.get("assistant_title"))
                        .font(.system(size: m.title, weight: .heavy))
                        .foregroundColor(theme.text)
                    Text(t.get("assistant_hint"))
                        .font(.system(size: m.small))
                        .foregroundColor(theme.muted)
                }
                Spacer(minLength: 0)
            }
            messages(m, width: width, you: t.get("you"), ai: cfg?.presenterName ?? "ORYKSA")
            if model.busy {
                Text(t.get("thinking"))
                    .font(.system(size: m.text))
                    .foregroundColor(theme.muted)
                    .accessibilityIdentifier("oryksa-tv-thinking")
            }
            // Where the phone stands while the QR card is closed, in the chosen language: when the phone
            // leaves, the person sees it here (the phone button then gives a new code).
            if let s = status {
                Text(s)
                    .font(.system(size: m.text, weight: .bold))
                    .foregroundColor(theme.accent)
                    .accessibilityIdentifier("oryksa-tv-phone-status")
            }
            if model.showPairing {
                OryksaPairingCard(tv: tv, theme: theme)
            }
            // One row that scrolls to the focused button: left and right always follow the order of the
            // buttons.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: m.px(20)) {
                    ForEach(buttons) { b in
                        OryksaTvButton(b.label, systemImage: b.icon, theme: theme, accessibilityID: b.id, action: b.run)
                            .focused($focus, equals: b.id)
                    }
                }
                .padding(.vertical, m.px(16))
                .padding(.horizontal, m.px(16))
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
        .padding(sidePanel ? m.px(40) : m.px(20))
    }

    private func messages(_ m: OryksaTvMetrics, width: CGFloat, you: String, ai: String) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: m.px(16)) {
                    ForEach(model.msgs) { msg in
                        HStack(spacing: 0) {
                            if msg.mine { Spacer(minLength: m.px(80)) }
                            OryksaTvMessageBubble(mine: msg.mine, who: msg.mine ? you : ai, text: msg.text, theme: theme, m: m)
                                .frame(maxWidth: width * (msg.mine ? 0.5 : 0.7), alignment: msg.mine ? .trailing : .leading)
                                .accessibilityIdentifier("oryksa-tv-msg-\(msg.id)")
                            if !msg.mine { Spacer(minLength: m.px(80)) }
                        }
                        .id(msg.id)
                    }
                }
                .padding(m.px(12))
            }
            .frame(maxHeight: .infinity)
            .onChange(of: model.msgs.count) { _ in
                if let last = model.msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
            }
        }
    }
}

/// One message. On tvOS each message can take the focus, so up and down scroll through the conversation.
struct OryksaTvMessageBubble: View {
    let mine: Bool
    let who: String
    let text: String
    let theme: OryksaTvTheme
    let m: OryksaTvMetrics

    private var face: some View {
        VStack(alignment: .leading, spacing: m.px(6)) {
            Text(who)
                .font(.system(size: m.small, weight: .bold))
                .foregroundColor(theme.muted)
            Text(text)
                .font(.system(size: m.text))
                .foregroundColor(theme.text)
                .lineSpacing(m.px(6))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, m.px(28))
        .padding(.vertical, m.px(18))
        .background(RoundedRectangle(cornerRadius: m.px(20), style: .continuous)
            .fill(mine ? theme.accent.opacity(0.35) : theme.surface))
    }

    var body: some View {
        #if os(tvOS)
        Button(action: {}) { face }
            .buttonStyle(OryksaTvRingStyle(theme: theme, m: m))
        #else
        face
        #endif
    }
}

/// A focus ring around a message (tvOS).
struct OryksaTvRingStyle: ButtonStyle {
    let theme: OryksaTvTheme
    let m: OryksaTvMetrics

    func makeBody(configuration: Configuration) -> some View {
        OryksaTvRingFace(configuration: configuration, theme: theme, m: m)
    }
}

private struct OryksaTvRingFace: View {
    let configuration: ButtonStyleConfiguration
    let theme: OryksaTvTheme
    let m: OryksaTvMetrics
    @Environment(\.isFocused) private var focused

    init(configuration: ButtonStyleConfiguration, theme: OryksaTvTheme, m: OryksaTvMetrics) {
        self.configuration = configuration; self.theme = theme; self.m = m
    }

    var body: some View {
        configuration.label
            .overlay(RoundedRectangle(cornerRadius: m.px(20), style: .continuous)
                .stroke(focused ? theme.focus : Color.clear, lineWidth: m.focusWidth))
    }
}

/// The typing sheet: the system keyboard opens from the field. Only the Send button sends (closing the
/// keyboard with Back must mean cancel); the keyboard's Done moves the focus to Send.
struct OryksaTvTypeSheet: View {
    let texts: OryksaTvTexts
    let theme: OryksaTvTheme
    let onSend: (String) -> Void
    let onCancel: () -> Void
    @State private var text = ""
    @FocusState private var field: Field?
    @Environment(\.oryksaTvMetrics) private var m

    private enum Field: Hashable { case input, send }

    init(texts: OryksaTvTexts, theme: OryksaTvTheme, onSend: @escaping (String) -> Void, onCancel: @escaping () -> Void) {
        self.texts = texts; self.theme = theme; self.onSend = onSend; self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: m.px(24)) {
            TextField(texts.get("type_message"), text: $text)
                .font(.system(size: m.text))
                .focused($field, equals: .input)
                .onSubmit { field = .send }
                .accessibilityIdentifier("oryksa-tv-type-field")
            HStack(spacing: m.px(20)) {
                OryksaTvButton(texts.get("send"), systemImage: "paperplane.fill", theme: theme, accessibilityID: "oryksa-tv-send") {
                    let v = text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !v.isEmpty { onSend(v) }
                }
                .focused($field, equals: .send)
                OryksaTvButton(texts.get("close"), systemImage: "xmark", theme: theme, accessibilityID: "oryksa-tv-type-close") {
                    onCancel()
                }
            }
        }
        .padding(m.px(40))
        .frame(maxWidth: m.px(1100))
    }
}

#if !os(macOS)
/// A see-through full-screen cover for the side panel (iOS and tvOS 16.4 or later; before, the panel is
/// shown over a dark background).
struct OryksaClearCover: ViewModifier {
    let enabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if enabled {
            if #available(iOS 16.4, tvOS 16.4, *) {
                content.presentationBackground(.clear)
            } else {
                content
            }
        } else {
            content
        }
    }
}
#endif

public extension View {
    /// Opens the assistant panel over this screen while `isPresented` is true. Back closes it and the
    /// focus goes back where it was.
    /// - sidePanel: a panel on the right instead of the whole screen.
    @MainActor
    func oryksaTvAssistant(isPresented: Binding<Bool>, tv: OryksaTv, appContext: (() -> OryksaAppContext?)? = nil,
                           sidePanel: Bool = false, theme: OryksaTvTheme = OryksaTvTheme()) -> some View {
        #if os(macOS)
        return sheet(isPresented: isPresented) {
            OryksaTvAssistant(tv: tv, appContext: appContext, sidePanel: sidePanel, theme: theme) {
                isPresented.wrappedValue = false
            }
            .frame(minWidth: 960, minHeight: 540)
        }
        #else
        return fullScreenCover(isPresented: isPresented) {
            OryksaTvAssistant(tv: tv, appContext: appContext, sidePanel: sidePanel, theme: theme) {
                isPresented.wrappedValue = false
            }
            .modifier(OryksaClearCover(enabled: sidePanel))
        }
        #endif
    }
}

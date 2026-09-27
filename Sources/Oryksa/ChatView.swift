// The ORYKSA chat for SwiftUI: name and photo of the AI from ORYKSA, with voice on iOS. License: MIT.
#if canImport(SwiftUI)
import SwiftUI

/// Colors of the chat. The defaults are the ORYKSA website chat colors.
public struct OryksaChatTheme {
    public var accent: Color
    public var ink: Color
    public var soft: Color
    public var background: Color
    public var muted: Color
    public init(accent: Color = Color(red: 0.357, green: 0.341, blue: 0.878),
                ink: Color = Color(red: 0.086, green: 0.106, blue: 0.239),
                soft: Color = Color(red: 0.933, green: 0.922, blue: 0.984),
                background: Color = .white,
                muted: Color = Color(red: 0.42, green: 0.447, blue: 0.502)) {
        self.accent = accent; self.ink = ink; self.soft = soft; self.background = background; self.muted = muted
    }
}

let oryksaTexts: [String: [String: String]] = [
    "en": ["talk": "Talk to", "ph": "Type your question", "send": "Send", "err": "Sorry, something went wrong. Try again.", "voice": "Talk by voice"],
    "pt": ["talk": "Falar com", "ph": "Escreve a tua pergunta", "send": "Enviar", "err": "Desculpa, algo correu mal. Tenta de novo.", "voice": "Falar por voz"],
    "br": ["talk": "Falar com", "ph": "Digite sua pergunta", "send": "Enviar", "err": "Desculpe, algo deu errado. Tente de novo.", "voice": "Falar por voz"],
    "es": ["talk": "Hablar con", "ph": "Escribe tu pregunta", "send": "Enviar", "err": "Lo siento, algo salió mal. Inténtalo de nuevo.", "voice": "Hablar por voz"],
]

func oryksaLang(_ l: String) -> String { oryksaTexts[l] != nil ? l : "en" }

private struct ChatMsg: Identifiable, Equatable {
    let id = UUID()
    let role: String
    let text: String
}

@MainActor
final class OryksaChatModel: ObservableObject {
    @Published var agent: OryksaAgent?
    @Published fileprivate var msgs: [ChatMsg] = []
    @Published var suggestions: [String] = []
    @Published var busy = false
    @Published var profanityReady = false
    let client: OryksaClient
    let lang: String
    let appContext: (() -> OryksaAppContext?)?

    init(client: OryksaClient, lang: String, appContext: (() -> OryksaAppContext?)? = nil) {
        self.client = client
        self.lang = oryksaLang(lang)
        self.appContext = appContext
    }

    /// A line said or heard in the voice screen goes to the chat too.
    func add(_ role: String, _ text: String) {
        suggestions = []
        msgs.append(ChatMsg(role: role, text: text))
    }

    func load() async {
        // Swear words the customer types show as asterisks (one list for every ORYKSA chat).
        Task { await OryksaProfanity.load(lang); profanityReady = true }
        guard agent == nil else { return }
        do {
            let a = try await client.agent()
            let hist = (try? await client.messages()) ?? []
            agent = a
            if hist.isEmpty {
                if let g = OryksaAgent.pick(a.greeting, lang), !g.isEmpty { msgs.append(ChatMsg(role: "assistant", text: g)) }
                suggestions = Array((OryksaAgent.pick(a.suggestions, lang) ?? []).prefix(4))
            } else {
                msgs = hist.map { ChatMsg(role: $0.role == "user" ? "user" : "assistant", text: $0.content) }
            }
        } catch {
            agent = OryksaAgent(name: "ORYKSA", avatar: "https://oryksa.com/assets/img/avatar_official_oryksa.png")
        }
    }

    func send(_ text: String) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty, !busy else { return }
        busy = true
        suggestions = []
        msgs.append(ChatMsg(role: "user", text: q))
        msgs.append(ChatMsg(role: "typing", text: "..."))
        let reply = try? await client.sendAndWait(q, appContext: appContext?())
        msgs.removeAll { $0.role == "typing" }
        msgs.append(ChatMsg(role: "assistant", text: (reply ?? nil) ?? (oryksaTexts[lang]?["err"] ?? "")))
        busy = false
    }
}

/// Text with **bold** parts (the server marks them, the app only draws them).
func oryksaBold(_ text: String) -> Text {
    let parts = text.components(separatedBy: "**")
    guard parts.count >= 3 else { return Text(text) }
    var out = Text("")
    for (i, p) in parts.enumerated() where !p.isEmpty {
        out = out + (i % 2 == 1 ? Text(p).bold() : Text(p))
    }
    return out
}

/// The ORYKSA chat panel: header with the photo and name of the AI, messages, suggestions, input
/// and (on iOS, when the plan has voice) the microphone that opens the voice conversation.
public struct OryksaChatView: View {
    @StateObject private var model: OryksaChatModel
    @State private var text = ""
    @State private var voiceOpen = false
    private let theme: OryksaChatTheme
    private let onClose: (() -> Void)?
    private let voice: Bool

    /// - appContext: where the customer is in your app right now (sent with each message).
    /// - voice: shows the microphone when the plan has voice (needs NSMicrophoneUsageDescription).
    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, voice: Bool = true, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: OryksaChatModel(client: client, lang: lang, appContext: appContext))
        self.theme = theme
        self.onClose = onClose
        self.voice = voice
    }

    private var tx: [String: String] { oryksaTexts[model.lang] ?? oryksaTexts["en"]! }

    public var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                OryksaAvatar(url: model.agent?.avatar, size: 46)
                VStack(alignment: .leading, spacing: 2) {
                    Text((model.agent?.name ?? "").uppercased())
                        .font(.system(size: 14, weight: .heavy)).kerning(2).foregroundColor(theme.ink)
                    let sub = model.agent.flatMap { OryksaAgent.pick($0.subtitle, model.lang) ?? $0.business } ?? ""
                    if !sub.isEmpty { Text(sub).font(.system(size: 12)).foregroundColor(theme.muted).lineLimit(1) }
                }
                Spacer()
                if let onClose = onClose {
                    Button(action: onClose) { Image(systemName: "xmark").foregroundColor(theme.muted) }
                        .accessibilityLabel("Close")
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(model.msgs) { m in
                            let mine = m.role == "user"
                            HStack {
                                if mine { Spacer(minLength: 40) }
                                oryksaBold(mine && model.profanityReady ? OryksaProfanity.mask(m.text, model.lang) : m.text)
                                    .font(.system(size: 14)).lineSpacing(3)
                                    .foregroundColor(mine ? .white : theme.ink)
                                    .padding(.horizontal, 14).padding(.vertical, 10)
                                    .background(mine ? theme.accent : theme.soft)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .opacity(m.role == "typing" ? 0.6 : 1)
                                    .textSelection(.enabled)
                                if !mine { Spacer(minLength: 40) }
                            }
                            .id(m.id)
                        }
                    }
                    .padding(16)
                }
                .onChange(of: model.msgs) { msgs in
                    if let last = msgs.last { withAnimation { proxy.scrollTo(last.id, anchor: .bottom) } }
                }
            }
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.suggestions, id: \.self) { s in
                            Button(s) { Task { await model.send(s) } }
                                .font(.system(size: 12.5)).foregroundColor(theme.accent)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .overlay(Capsule().stroke(Color(red: 0.863, green: 0.863, blue: 0.961)))
                        }
                    }.padding(.horizontal, 16)
                }.padding(.bottom, 10)
            }
            Divider()
            HStack(spacing: 0) {
                TextField(tx["ph"] ?? "", text: $text)
                    .font(.system(size: 14)).foregroundColor(theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .submitLabel(.send)
                    .onSubmit { let t = text; text = ""; Task { await model.send(t) } }
                #if os(iOS)
                if voice && (model.agent?.voiceReplies ?? false) && text.isEmpty {
                    Button { voiceOpen = true } label: {
                        Image(systemName: "mic").font(.system(size: 18)).foregroundColor(theme.accent).padding(.horizontal, 12)
                    }
                    .accessibilityLabel(tx["voice"] ?? "Voice")
                    .disabled(model.busy)
                }
                #endif
                Button {
                    let t = text; text = ""; Task { await model.send(t) }
                } label: {
                    Text((tx["send"] ?? "Send").uppercased()).font(.system(size: 14, weight: .heavy)).kerning(1.2)
                        .foregroundColor(.white).padding(.horizontal, 18).frame(maxHeight: .infinity)
                        .background(theme.accent)
                }
                .disabled(model.busy)
            }
            .frame(height: 50)
            (Text("POWERED BY ") + Text("ORYKSA").foregroundColor(theme.accent).fontWeight(.heavy))
                .font(.system(size: 10.5)).kerning(1.3).foregroundColor(.gray)
                .padding(.top, 6).padding(.bottom, 8)
        }
        .background(theme.background)
        .task { await model.load() }
        #if os(iOS)
        .fullScreenCover(isPresented: $voiceOpen) {
            if let a = model.agent {
                OryksaVoiceSheet(client: model.client, agent: a, lang: model.lang, theme: theme, appContext: model.appContext,
                                 onUserText: { model.add("user", $0) }, onReply: { model.add("assistant", $0) }) { voiceOpen = false }
            }
        }
        #endif
    }
}

struct OryksaAvatar: View {
    let url: String?
    let size: CGFloat
    var body: some View {
        AsyncImage(url: URL(string: url ?? "")) { img in img.resizable().scaledToFill() } placeholder: {
            Color(red: 0.933, green: 0.922, blue: 0.984)
        }
        .frame(width: size, height: size).clipShape(Circle())
    }
}

/// Floating "Talk to name" button with the photo of the AI. Opens the chat in a sheet.
public struct OryksaChatButton: View {
    private let client: OryksaClient
    private let lang: String
    private let theme: OryksaChatTheme
    private let appContext: (() -> OryksaAppContext?)?
    private let voice: Bool
    @State private var agent: OryksaAgent?
    @State private var open = false

    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, voice: Bool = true) {
        self.client = client
        self.lang = oryksaLang(lang)
        self.theme = theme
        self.appContext = appContext
        self.voice = voice
    }

    public var body: some View {
        Button { open = true } label: {
            HStack(spacing: 10) {
                OryksaAvatar(url: agent?.avatar, size: 42).overlay(Circle().stroke(Color.white, lineWidth: 2))
                Text("\(oryksaTexts[lang]?["talk"] ?? "Talk to") \(agent?.name ?? "ORYKSA")".uppercased())
                    .font(.system(size: 13, weight: .heavy)).kerning(1).foregroundColor(.white)
            }
            .padding(.leading, 8).padding(.trailing, 18).padding(.vertical, 8)
            .background(Capsule().fill(theme.accent))
            .shadow(color: Color.black.opacity(0.25), radius: 12, y: 6)
        }
        .buttonStyle(.plain)
        .task { if agent == nil { agent = try? await client.agent() } }
        .sheet(isPresented: $open) {
            OryksaChatView(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice) { open = false }
        }
    }
}

#if canImport(UIKit)
import UIKit

/// The chat for UIKit apps: present it with `present(OryksaChatViewController(client: client), animated: true)`.
public final class OryksaChatViewController: UIHostingController<AnyView> {
    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil) {
        super.init(rootView: AnyView(EmptyView()))
        rootView = AnyView(OryksaChatView(client: client, lang: lang, theme: theme, appContext: appContext) { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}
#endif
#endif

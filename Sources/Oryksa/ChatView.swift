// The ORYKSA chat for SwiftUI: name and photo of the AI from ORYKSA, with voice on iOS. License: MIT.
#if canImport(SwiftUI)
import SwiftUI
#if os(macOS)
import AppKit
#endif

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
    "en": ["talk": "Talk to", "ph": "Type your question", "send": "Send", "err": "Sorry, something went wrong. Try again.", "voice": "Talk by voice", "copy": "Copy", "open": "Open", "attach": "Attach", "gallery": "Photo library", "camera": "Camera", "document": "Document", "big": "The file is too large (max 8 MB).", "attachErr": "Could not attach the file."],
    "pt": ["talk": "Falar com", "ph": "Escreve a tua pergunta", "send": "Enviar", "err": "Desculpa, algo correu mal. Tenta de novo.", "voice": "Falar por voz", "copy": "Copiar", "open": "Abrir", "attach": "Anexar", "gallery": "Foto da galeria", "camera": "Câmara", "document": "Documento", "big": "O ficheiro é demasiado grande (máx. 8 MB).", "attachErr": "Não foi possível anexar o ficheiro."],
    "br": ["talk": "Falar com", "ph": "Digite sua pergunta", "send": "Enviar", "err": "Desculpe, algo deu errado. Tente de novo.", "voice": "Falar por voz", "copy": "Copiar", "open": "Abrir", "attach": "Anexar", "gallery": "Foto da galeria", "camera": "Câmera", "document": "Documento", "big": "O arquivo é grande demais (máx. 8 MB).", "attachErr": "Não foi possível anexar o arquivo."],
    "es": ["talk": "Hablar con", "ph": "Escribe tu pregunta", "send": "Enviar", "err": "Lo siento, algo salió mal. Inténtalo de nuevo.", "voice": "Hablar por voz", "copy": "Copiar", "open": "Abrir", "attach": "Adjuntar", "gallery": "Foto de la galería", "camera": "Cámara", "document": "Documento", "big": "El archivo es demasiado grande (máx. 8 MB).", "attachErr": "No se pudo adjuntar el archivo."],
]

func oryksaLang(_ l: String) -> String { oryksaTexts[l] != nil ? l : "en" }

private struct ChatMsg: Identifiable, Equatable {
    let id = UUID()
    let role: String
    let text: String
    /// A photo the customer sent (shown as a thumbnail in the bubble).
    var image: Data? = nil
    /// The name of a document the customer sent.
    var fileName: String? = nil
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

    /// Sends what the customer typed, with a photo or a document when they attached one.
    func send(_ text: String, image: OryksaImage? = nil, file: OryksaFile? = nil) async {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty || image != nil || file != nil, !busy else { return }
        busy = true
        suggestions = []
        msgs.append(ChatMsg(role: "user", text: q, image: image?.data, fileName: file?.name))
        msgs.append(ChatMsg(role: "typing", text: "..."))
        let reply = try? await client.sendAndWait(q, appContext: appContext?(), image: image, file: file)
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

/// The inside of a message bubble: the photo or the document the customer sent, then the text.
private struct OryksaBubble: View {
    let m: ChatMsg
    let shown: String
    let theme: OryksaChatTheme
    let onLink: OryksaLinkHandler?

    var body: some View {
        let mine = m.role == "user"
        VStack(alignment: .leading, spacing: 8) {
            if let data = m.image, let img = oryksaThumb(data) {
                img.resizable().scaledToFill().frame(width: 200, height: 160).clipped()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            if let name = m.fileName {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text").font(.system(size: 18)).foregroundColor(mine ? .white : theme.accent)
                    Text(name).font(.system(size: 13, weight: .semibold)).foregroundColor(mine ? .white : theme.ink).lineLimit(2)
                }
            }
            if !m.text.isEmpty {
                Text(oryksaRichText(shown, linkColor: mine ? .white : theme.accent))
                    .font(.system(size: 14)).lineSpacing(3)
                    .foregroundColor(mine ? .white : theme.ink)
                    .tint(mine ? .white : theme.accent)
                    .modifier(OryksaLinkRouting(onLink: onLink))
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(mine ? theme.accent : theme.soft)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .opacity(m.role == "typing" ? 0.6 : 1)
        .textSelection(.enabled)
    }
}

/// A picture from its bytes, for the bubble.
func oryksaThumb(_ data: Data) -> Image? {
    #if canImport(UIKit)
    return UIImage(data: data).map { Image(uiImage: $0) }
    #elseif canImport(AppKit)
    return NSImage(data: data).map { Image(nsImage: $0) }
    #else
    return nil
    #endif
}

/// The ORYKSA chat panel: header with the photo and name of the AI, messages, suggestions, input
/// and (on iOS, when the plan has voice) the microphone that opens the voice conversation.
public struct OryksaChatView: View {
    @StateObject private var model: OryksaChatModel
    @State private var text = ""
    @State private var voiceOpen = false
    @State private var note: String?
    private let theme: OryksaChatTheme
    private let onClose: (() -> Void)?
    private let voice: Bool
    private let attachments: Bool
    private let onLink: OryksaLinkHandler?

    /// - appContext: where the customer is in your app right now (sent with each message).
    /// - voice: shows the microphone when the plan has voice (needs NSMicrophoneUsageDescription).
    /// - attachments: shows the attach button on iOS (photo library, camera, document); the camera needs
    ///   NSCameraUsageDescription in Info.plist and only shows when it is there.
    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, voice: Bool = true, attachments: Bool = true,
                onClose: (() -> Void)? = nil) {
        self.init(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice, attachments: attachments,
                  onLink: nil, onClose: onClose)
    }

    /// The same chat with `onLink`: what your app does with a link the AI gave (see
    /// `OryksaLinkHandler`). Nil: the browser or the app that owns the address opens it.
    /// (A separate init, so `OryksaChatView(client: client) { close() }` keeps closing the chat.)
    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, voice: Bool = true, attachments: Bool = true,
                onLink: OryksaLinkHandler?, onClose: (() -> Void)? = nil) {
        _model = StateObject(wrappedValue: OryksaChatModel(client: client, lang: lang, appContext: appContext))
        self.theme = theme
        self.onClose = onClose
        self.voice = voice
        self.attachments = attachments
        self.onLink = onLink
    }

    /// A short line over the input (file too large, could not attach), for a few seconds.
    private func show(_ n: String?) {
        guard let n = n else { return }
        note = n
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) { if note == n { note = nil } }
    }

    #if os(iOS)
    private func attached(_ r: OryksaPicked) {
        switch r {
        case .cancelled: return
        case .failed: show(tx["attachErr"])
        case .picked(.tooBig): show(tx["big"])
        case .picked(.image(let img)): let t = text; text = ""; Task { await model.send(t, image: img) }
        case .picked(.file(let f)): let t = text; text = ""; Task { await model.send(t, file: f) }
        }
    }
    #endif

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
                            VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                if mine { Spacer(minLength: 40) }
                                OryksaBubble(m: m, shown: mine && model.profanityReady ? OryksaProfanity.mask(m.text, model.lang) : m.text,
                                             theme: theme, onLink: onLink)
                                if !mine { Spacer(minLength: 40) }
                            }
                            // A card with an Open button for each link of the reply (owner 2026-11-21: the links
                            // were plain text), then the copy button (same as the ORYKSA apps and extension).
                            if !mine && m.role != "typing" && !m.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                ForEach(oryksaLinksIn(m.text), id: \.self) { u in
                                    HStack {
                                        OryksaLinkCard(url: u, client: model.client, openLabel: tx["open"] ?? "Open", onLink: onLink,
                                                       accent: theme.accent, ink: theme.ink, muted: theme.muted, background: theme.background)
                                        Spacer(minLength: 40)
                                    }
                                    .padding(.top, 4)
                                }
                                OryksaCopyButton(text: m.text.replacingOccurrences(of: "**", with: ""), label: tx["copy"] ?? "Copy", color: theme.muted)
                            }
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
            if let n = note {
                Text(n).font(.system(size: 12.5)).foregroundColor(.white)
                    .padding(.horizontal, 12).padding(.vertical, 8)
                    .background(Capsule().fill(theme.ink.opacity(0.9)))
                    .padding(.bottom, 8)
            }
            Divider()
            HStack(spacing: 0) {
                TextField(tx["ph"] ?? "", text: $text)
                    .font(.system(size: 14)).foregroundColor(theme.ink)
                    .padding(.horizontal, 16).padding(.vertical, 14)
                    .submitLabel(.send)
                    .onSubmit { let t = text; text = ""; Task { await model.send(t) } }
                #if os(iOS)
                if attachments {
                    OryksaAttachButton(tx: tx, color: theme.accent, disabled: model.busy) { attached($0) }
                }
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
                                 onUserText: { model.add("user", $0) }, onReply: { model.add("assistant", $0) },
                                 onClose: { voiceOpen = false }, onLink: onLink)
            }
        }
        #endif
    }
}

#if os(iOS)
/// The paperclip in the input: a menu with the photo library, the camera (when the app can use it)
/// and documents.
struct OryksaAttachButton: View {
    let tx: [String: String]
    let color: Color
    let disabled: Bool
    let onPicked: (OryksaPicked) -> Void
    @State private var menu = false
    @State private var sheet: OryksaAttachSource?
    @State private var camera = false

    var body: some View {
        Button { menu = true } label: {
            Image(systemName: "paperclip").font(.system(size: 18)).foregroundColor(color).padding(.horizontal, 10)
        }
        .accessibilityLabel(tx["attach"] ?? "Attach")
        .disabled(disabled)
        .confirmationDialog(tx["attach"] ?? "Attach", isPresented: $menu, titleVisibility: .hidden) {
            Button(tx["gallery"] ?? "Photo library") { sheet = .gallery }
            if oryksaCameraAvailable { Button(tx["camera"] ?? "Camera") { camera = true } }
            Button(tx["document"] ?? "Document") { sheet = .document }
        }
        .sheet(item: $sheet) { s in
            OryksaAttachPicker(source: s) { r in sheet = nil; onPicked(r) }.ignoresSafeArea()
        }
        .fullScreenCover(isPresented: $camera) {
            OryksaAttachPicker(source: .camera) { r in camera = false; onPicked(r) }.ignoresSafeArea()
        }
    }
}
#endif

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
    private let attachments: Bool
    private let onLink: OryksaLinkHandler?
    @State private var agent: OryksaAgent?
    @State private var open = false

    /// - attachments: shows the attach button in the chat (photo library, camera, document).
    /// - onLink: what your app does with a link the AI gave (see `OryksaLinkHandler`), for
    ///   example your own product screen for the links of your site.
    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, voice: Bool = true, attachments: Bool = true,
                onLink: OryksaLinkHandler? = nil) {
        self.client = client
        self.lang = oryksaLang(lang)
        self.theme = theme
        self.appContext = appContext
        self.voice = voice
        self.attachments = attachments
        self.onLink = onLink
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
            OryksaChatView(client: client, lang: lang, theme: theme, appContext: appContext, voice: voice, attachments: attachments,
                           onLink: onLink) { open = false }
        }
    }
}

#if canImport(UIKit)
import UIKit

/// The chat for UIKit apps: present it with `present(OryksaChatViewController(client: client), animated: true)`.
public final class OryksaChatViewController: UIHostingController<AnyView> {
    /// - attachments: shows the attach button (photo library, camera, document).
    /// - onLink: what your app does with a link the AI gave (see `OryksaLinkHandler`).
    public init(client: OryksaClient, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, attachments: Bool = true, onLink: OryksaLinkHandler? = nil) {
        super.init(rootView: AnyView(EmptyView()))
        rootView = AnyView(OryksaChatView(client: client, lang: lang, theme: theme, appContext: appContext, attachments: attachments,
                                          onLink: onLink) { [weak self] in
            self?.dismiss(animated: true)
        })
    }

    @available(*, unavailable)
    required dynamic init?(coder aDecoder: NSCoder) { fatalError("init(coder:) is not supported") }
}
#endif
#endif

/// Small copy button under a reply: copies the text and shows a check for a moment.
struct OryksaCopyButton: View {
    let text: String
    let label: String
    let color: Color
    @State private var done = false

    var body: some View {
        Button {
            #if os(iOS)
            UIPasteboard.general.string = text
            #elseif os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #endif
            done = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { done = false }
        } label: {
            Image(systemName: done ? "checkmark" : "doc.on.doc")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(color)
                .frame(width: 28, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

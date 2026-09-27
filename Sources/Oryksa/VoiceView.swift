// ORYKSA voice screen for SwiftUI (iOS), the same as the ORYKSA app. License: MIT.
#if os(iOS) && canImport(SwiftUI)
import SwiftUI

let oryksaVoiceTexts: [String: [String: String]] = [
    "en": ["listening": "I'm listening", "listeningSub": "Speak to me. You can cut me off any time.", "hearing": "Go on, I am listening.",
           "thinking": "One moment...", "muted": "Paused", "mutedSub": "Tap the mic to talk again.",
           "micError": "Microphone unavailable", "micErrorSub": "Allow microphone access, or close other apps using it.",
           "noisy": "Too much background noise", "noisySub": "I cannot tell your voice from the noise. Move somewhere quieter, or type to me.",
           "notUnderstood": "I could not understand", "notUnderstoodSub": "Say it again, please.",
           "tapToSend": "Tap the picture to send what you said.", "mute": "Mute", "unmute": "Unmute", "close": "Close"],
    "pt": ["listening": "Estou a ouvir", "listeningSub": "Fala comigo. Podes interromper-me quando quiseres.", "hearing": "Continua, estou a ouvir.",
           "thinking": "Um momento...", "muted": "Em pausa", "mutedSub": "Toca no microfone para voltar a falar.",
           "micError": "Microfone indisponível", "micErrorSub": "Permite o acesso ao microfone, ou fecha outras apps que o estejam a usar.",
           "noisy": "Demasiado barulho", "noisySub": "Não consigo distinguir a tua voz do barulho. Vai para um sítio mais calmo, ou escreve-me.",
           "notUnderstood": "Não percebi", "notUnderstoodSub": "Diz outra vez, por favor.",
           "tapToSend": "Toca na imagem para enviar o que disseste.", "mute": "Silenciar", "unmute": "Ativar som", "close": "Fechar"],
    "br": ["listening": "Estou ouvindo", "listeningSub": "Fale comigo. Você pode me interromper quando quiser.", "hearing": "Continue, estou ouvindo.",
           "thinking": "Um momento...", "muted": "Em pausa", "mutedSub": "Toque no microfone para voltar a falar.",
           "micError": "Microfone indisponível", "micErrorSub": "Permita o acesso ao microfone, ou feche outros apps que estejam usando.",
           "noisy": "Barulho demais", "noisySub": "Não consigo separar sua voz do barulho. Vá para um lugar mais calmo, ou digite para mim.",
           "notUnderstood": "Não entendi", "notUnderstoodSub": "Fale de novo, por favor.",
           "tapToSend": "Toque na imagem para enviar o que você disse.", "mute": "Silenciar", "unmute": "Ativar som", "close": "Fechar"],
    "es": ["listening": "Te escucho", "listeningSub": "Háblame. Puedes interrumpirme cuando quieras.", "hearing": "Sigue, te escucho.",
           "thinking": "Un momento...", "muted": "En pausa", "mutedSub": "Toca el micrófono para volver a hablar.",
           "micError": "Micrófono no disponible", "micErrorSub": "Permite el acceso al micrófono, o cierra otras apps que lo estén usando.",
           "noisy": "Demasiado ruido", "noisySub": "No distingo tu voz del ruido. Ve a un sitio más tranquilo, o escríbeme.",
           "notUnderstood": "No te entendí", "notUnderstoodSub": "Dilo otra vez, por favor.",
           "tapToSend": "Toca la imagen para enviar lo que dijiste.", "mute": "Silenciar", "unmute": "Activar sonido", "close": "Cerrar"],
]

/// Full-screen voice conversation: the photo of the AI with a halo, "I'm listening" / her answer,
/// Mute and Close. It starts listening when it appears and closes the microphone when it goes.
public struct OryksaVoiceView: View {
    @ObservedObject var controller: OryksaVoiceController
    let agent: OryksaAgent
    let lang: String
    let theme: OryksaChatTheme
    let onClose: () -> Void
    @State private var pulse = false

    public init(controller: OryksaVoiceController, agent: OryksaAgent, lang: String = "en",
                theme: OryksaChatTheme = OryksaChatTheme(), onClose: @escaping () -> Void) {
        self.controller = controller
        self.agent = agent
        self.lang = oryksaVoiceTexts[lang] != nil ? lang : "en"
        self.theme = theme
        self.onClose = onClose
    }

    private var t: [String: String] { oryksaVoiceTexts[lang]! }

    private var texts: (String, String) {
        switch controller.phase {
        case .starting, .listening: return (t["listening"]!, t["listeningSub"]!)
        case .hearing: return (t["listening"]!, t["hearing"]!)
        case .thinking: return (controller.lastHeard.isEmpty ? "..." : controller.lastHeard, t["thinking"]!)
        case .speaking: return (agent.name, controller.lastReply)
        case .muted: return (t["muted"]!, t["mutedSub"]!)
        case .micError: return (t["micError"]!, t["micErrorSub"]!)
        case .noisy: return (t["noisy"]!, t["noisySub"]!)
        case .notUnderstood: return (t["notUnderstood"]!, t["notUnderstoodSub"]!)
        }
    }

    public var body: some View {
        let (title, sub) = texts
        let active = controller.phase == .hearing || controller.phase == .speaking
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                OryksaAvatar(url: agent.avatar, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name).font(.system(size: 14.5, weight: .bold)).foregroundColor(theme.ink)
                    if let b = agent.business, !b.isEmpty { Text(b).font(.system(size: 11)).foregroundColor(theme.muted).lineLimit(1) }
                }
                Spacer()
                Button(action: close) { Image(systemName: "xmark").foregroundColor(theme.muted) }
                    .accessibilityLabel(t["close"]!)
            }
            .padding(.horizontal, 16).padding(.top, 12)
            Spacer()
            ZStack {
                ForEach(Array([(236.0, 0.06), (184.0, 0.09), (136.0, 0.13)].enumerated()), id: \.offset) { i, r in
                    Circle().fill(theme.accent.opacity(r.1))
                        .frame(width: r.0, height: r.0)
                        .scaleEffect(active && pulse ? 1.07 : 1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true).delay(Double(i) * 0.125), value: pulse)
                }
                OryksaAvatar(url: agent.avatar, size: 124)
            }
            .frame(width: 250, height: 250)
            .onTapGesture { controller.sendNow() }
            Text(title).font(.system(size: 22, weight: .bold)).foregroundColor(theme.ink).multilineTextAlignment(.center)
                .padding(.top, 14).padding(.horizontal, 30)
            Text(sub).font(.system(size: 13.5)).foregroundColor(theme.muted).multilineTextAlignment(.center)
                .lineSpacing(4).padding(.top, 8).padding(.horizontal, 30)
            if controller.phase == .hearing {
                Text(t["tapToSend"]!).font(.system(size: 11.5)).foregroundColor(.gray).padding(.top, 10)
            }
            HStack(spacing: 46) {
                circleButton(controller.phase == .muted ? "mic.slash" : "mic",
                             controller.phase == .muted ? t["unmute"]! : t["mute"]!, cancel: false) { controller.toggleMute() }
                circleButton("xmark", t["close"]!, cancel: true, action: close)
            }
            .padding(.top, 20)
            Spacer()
            (Text("POWERED BY ") + Text("ORYKSA").foregroundColor(theme.accent).fontWeight(.heavy))
                .font(.system(size: 10.5)).kerning(1.3).foregroundColor(.gray).padding(.bottom, 22)
        }
        .background(LinearGradient(colors: [theme.background, theme.soft], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        .onAppear { pulse = true; controller.start() }
        .onDisappear { controller.close() }
    }

    private func close() {
        controller.close()
        onClose()
    }

    private func circleButton(_ icon: String, _ label: String, cancel: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 22))
                    .foregroundColor(cancel ? Color(red: 0.878, green: 0.353, blue: 0.322) : theme.muted)
                    .frame(width: 58, height: 58)
                    .background(Circle().fill(cancel ? Color(red: 0.992, green: 0.941, blue: 0.937) : theme.background))
                    .overlay(Circle().stroke(cancel ? Color(red: 0.953, green: 0.753, blue: 0.745) : Color(white: 0.92), lineWidth: 1.5))
                Text(label).font(.system(size: 12))
                    .foregroundColor(cancel ? Color(red: 0.878, green: 0.353, blue: 0.322) : theme.muted)
            }
        }
        .buttonStyle(.plain)
    }
}

/// The voice screen with its own controller (kept for as long as the screen is open).
public struct OryksaVoiceSheet: View {
    @StateObject private var controller: OryksaVoiceController
    let agent: OryksaAgent
    let lang: String
    let theme: OryksaChatTheme
    let onClose: () -> Void

    public init(client: OryksaClient, agent: OryksaAgent, lang: String = "en", theme: OryksaChatTheme = OryksaChatTheme(),
                appContext: (() -> OryksaAppContext?)? = nil, onUserText: ((String) -> Void)? = nil,
                onReply: ((String) -> Void)? = nil, onClose: @escaping () -> Void) {
        _controller = StateObject(wrappedValue: OryksaVoiceController(client: client, appContext: appContext,
                                                                      onUserText: onUserText, onReply: onReply))
        self.agent = agent
        self.lang = lang
        self.theme = theme
        self.onClose = onClose
    }

    public var body: some View {
        OryksaVoiceView(controller: controller, agent: agent, lang: lang, theme: theme, onClose: onClose)
    }
}
#endif

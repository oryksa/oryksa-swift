<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# ORYKSA for iOS (Swift)

[![English](https://img.shields.io/badge/English-30363d?style=for-the-badge)](README.md) [![Português](https://img.shields.io/badge/Portugu%C3%AAs-0891b2?style=for-the-badge)](README.pt.md) [![Español](https://img.shields.io/badge/Espa%C3%B1ol-30363d?style=for-the-badge)](README.es.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-30363d?style=for-the-badge)](README.fr.md)

<p align="center"><a href="https://developer.oryksa.com/pt/sdks"><img src="https://developer.oryksa.com/assets/img/sdk/oryksa-sdks-pt.gif" width="760" alt="SDKs ORYKSA: o chat e a voz da IA no iOS, Android, Flutter, React Native e na web"></a></p>

SDK oficial Swift da **ORYKSA AI Employees**. Põe dentro da tua app iOS ou macOS um colaborador de IA que já conhece o teu negócio: um chat SwiftUI (e UIKit) pronto com o mesmo aspeto do chat do site da ORYKSA, o nome e a foto da tua IA vindos da tua conta ORYKSA, em inglês, português e espanhol.

* Documentação: https://developer.oryksa.com/pt/sdks
* API: `https://api.oryksa.com/v1`
* iOS 15+, macOS 12+, sem dependências.

## Capturas de ecrã

<p align="center"><img src="docs/screenshots/ios_product_pt.png" width="190" alt="Página de produto com o botão do chat"> <img src="docs/screenshots/ios_chat_pt.png" width="190" alt="Chat"> <img src="docs/screenshots/ios_theme_pt.png" width="190" alt="Chat com o tema do README"> <img src="docs/screenshots/ios_voice_pt.png" width="190" alt="Voz"></p>

Ecrãs reais da app de exemplo deste repositório, captados pelo CI num simulador com uma conta de teste da ORYKSA. O chat verde usa o código de *Cores e tema*, mais abaixo.

## Instalar (Swift Package Manager)

No Xcode: **File > Add Package Dependencies**, cola `https://github.com/oryksa/oryksa-swift` e escolhe a versão `1.0.0`. Ou no `Package.swift`:

```swift
.package(url: "https://github.com/oryksa/oryksa-swift", from: "1.0.0")
```

CocoaPods:

```ruby
pod 'Oryksa', :git => 'https://github.com/oryksa/oryksa-swift.git', :tag => '1.0.0'
```

## Para que serve

O SDK põe o chat e a voz da ORYKSA dentro da tua app para atender os **clientes do teu negócio**: eles perguntam, compram e marcam. A IA responde com o teu Brain, os teus produtos e serviços, com o nome, a foto e a voz que escolheste em *A tua IA*, e guarda leads, marcações e vendas nas Atividades da tua conta ORYKSA. **Não** é uma interface para o dono: ninguém altera definições, lê Atividades ou dá ordens à ORYKSA através do SDK. Mais: https://help.oryksa.com/pt/a/sdks-what-they-do

Os palavrões que o cliente escreve aparecem como asteriscos no chat (a mesma lista de todos os chats da ORYKSA, carregada de `https://app.oryksa.com/widget/profanity.json` e guardada durante 24 horas). As respostas da IA já vêm filtradas do servidor.

## Voz e contexto da app (1.1)

O chat mostra um microfone quando o teu plano tem voz. Abre o ecrã de voz com o mesmo comportamento da app ORYKSA: o microfone fica aberto enquanto ela fala e só uma voz humana a interrompe (escrever, a TV e o eco dela própria não); ela para na palavra e o texto fica no chat; um sussurro recebe uma resposta sussurrada; se a voz dela falhar, aparece o texto (nunca uma voz de robô).

Permissão do microfone: adiciona `NSMicrophoneUsageDescription` ao Info.plist (a voz é só para iOS).

```swift
OryksaChatButton(client: client, lang: "pt",
                 appContext: { OryksaAppContext(screen: "product", title: "Sky Beginner Snowboard, 489.95") })
```

## Como funciona (e porque é que a chave fica segura)

1. O teu **servidor** guarda a chave secreta da API (`oryk_live_...`, criada em developer.oryksa.com) e cria um **token de sessão** de curta duração para cada utilizador com sessão iniciada, com `POST /v1/sessions`.
2. A tua **app** recebe só esse token de sessão (`oryk_cs_...`). A chave secreta nunca entra na app.
3. Cada resposta da IA conta como uma interação do teu plano ORYKSA, tal como no WhatsApp.

## SwiftUI

```swift
import Oryksa

let client = OryksaClient(getToken: {
    try await MyBackend.fetchOryksaToken() // devolve "oryk_cs_..."
})

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            MyScreens()
            OryksaChatButton(client: client, lang: "en").padding() // en, pt, br, es
        }
    }
}
```

Outras peças: `OryksaChatView(client: client)` (o painel em qualquer sítio), `OryksaChatTheme` (cores) e, para UIKit, `present(OryksaChatViewController(client: client), animated: true)`.

Sem a interface: `try await client.agent()`, `try await client.sendAndWait("Are you open on Saturday?")`, `try await client.messages()`.

## Mantém a IA sincronizada com a tua app

No teu servidor (por exemplo com `@oryksa/sdk` em Node): `oryksa.learnApp({ name, description, screens, faq })`.

## Erros

As chamadas falhadas lançam `OryksaError` com `status`, `code` (por exemplo `interaction_limit_reached`, `rate_limited`, `plan_required`) e `message`.

## Cores e tema

O `OryksaChatTheme` tem cinco cores: `accent` (botões, balões do visitante, ligações), `ink` (texto principal), `soft` (balões da IA), `background` (painel) e `muted` (texto secundário). Cada uma é uma `Color` do SwiftUI e tem um valor por omissão, por isso só passas as que queres mudar.

```swift
let theme = OryksaChatTheme(accent: Color(red: 0.05, green: 0.54, blue: 0.42))

OryksaChatButton(client: client, lang: "en", theme: theme)
// or the panel: OryksaChatView(client: client, theme: theme)
// or UIKit: OryksaChatViewController(client: client, theme: theme)
```

Não há tema escuro automático: para o modo escuro, passa as tuas próprias cores escuras.

---

## Sobre o autor

**Weslley Harakawa** - Fundador da ORYKSA AI. Em Lisboa, Portugal. Especialidades: inteligência artificial, desenvolvimento web e mobile, tokenização em blockchain. Formação: University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSA)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda

<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# ORYKSA for iOS (Swift)

Official Swift SDK for **ORYKSA AI Employees**. Put an AI employee that already knows your business inside your iOS or macOS app: a ready SwiftUI (and UIKit) chat with the same look as the ORYKSA website chat, the name and photo of your AI from your ORYKSA account, in English, Portuguese (Portugal and Brazil) and Spanish.

* Docs: https://developer.oryksa.com/en/sdks
* API: `https://api.oryksa.com/v1`
* iOS 15+, macOS 12+, no dependencies.

## Install (Swift Package Manager)

In Xcode: **File > Add Package Dependencies**, paste `https://github.com/oryksa/oryksa-swift` and pick version `1.0.0`. Or in `Package.swift`:

```swift
.package(url: "https://github.com/oryksa/oryksa-swift", from: "1.0.0")
```

CocoaPods:

```ruby
pod 'Oryksa', :git => 'https://github.com/oryksa/oryksa-swift.git', :tag => '1.0.0'
```

## How it works (and why the key stays safe)

1. Your **server** keeps the secret API key (`oryk_live_...`, created at developer.oryksa.com) and creates a short-lived **session token** for each signed-in user with `POST /v1/sessions`.
2. Your **app** receives only that session token (`oryk_cs_...`). The secret key never goes into the app.
3. Every AI reply counts as one interaction of your ORYKSA plan, the same as on WhatsApp.

## SwiftUI

```swift
import Oryksa

let client = OryksaClient(getToken: {
    try await MyBackend.fetchOryksaToken() // returns "oryk_cs_..."
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

Other pieces: `OryksaChatView(client: client)` (the panel anywhere), `OryksaChatTheme` (colors), and for UIKit `present(OryksaChatViewController(client: client), animated: true)`.

Without the UI: `try await client.agent()`, `try await client.sendAndWait("Are you open on Saturday?")`, `try await client.messages()`.

## Keep the AI in sync with your app

On your server (for example with `@oryksa/sdk` on Node): `oryksa.learnApp({ name, description, screens, faq })`.

## Errors

Failed calls throw `OryksaError` with `status`, `code` (for example `interaction_limit_reached`, `rate_limited`, `plan_required`) and `message`.

---

## Português (Portugal)

SDK oficial Swift da **ORYKSA AI Employees**: põe na tua app iOS um colaborador de IA que já conhece o teu negócio, com um chat SwiftUI pronto igual ao chat do site da ORYKSA, com o nome e a foto da tua IA. O teu servidor cria o token de sessão (`POST /v1/sessions`) e a app usa `OryksaClient(getToken:)` com `OryksaChatButton(client: client, lang: "pt")`. Cada resposta da IA conta como uma interação do teu plano.

## Português (Brasil)

SDK oficial Swift da **ORYKSA AI Employees**: coloque no seu app iOS um colaborador de IA que já conhece o seu negócio, com um chat SwiftUI pronto igual ao chat do site da ORYKSA, com o nome e a foto da sua IA. Seu servidor cria o token de sessão (`POST /v1/sessions`) e o app usa `OryksaClient(getToken:)` com `OryksaChatButton(client: client, lang: "br")`. Cada resposta da IA conta como uma interação do seu plano.

## Español

SDK oficial de Swift de **ORYKSA AI Employees**: pon en tu app iOS un empleado de IA que ya conoce tu negocio, con un chat SwiftUI listo igual al chat de la web de ORYKSA, con el nombre y la foto de tu IA. Tu servidor crea el token de sesión (`POST /v1/sessions`) y la app usa `OryksaClient(getToken:)` con `OryksaChatButton(client: client, lang: "es")`. Cada respuesta de la IA cuenta como una interacción de tu plan.

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda

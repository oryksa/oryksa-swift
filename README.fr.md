<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# ORYKSA for iOS (Swift)

[![English](https://img.shields.io/badge/English-30363d?style=for-the-badge)](README.md) [![Português](https://img.shields.io/badge/Portugu%C3%AAs-30363d?style=for-the-badge)](README.pt.md) [![Español](https://img.shields.io/badge/Espa%C3%B1ol-30363d?style=for-the-badge)](README.es.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-0891b2?style=for-the-badge)](README.fr.md)

<p align="center"><a href="https://developer.oryksa.com/fr/sdks"><img src="https://developer.oryksa.com/assets/img/sdk/oryksa-sdks-fr.gif" width="760" alt="SDK ORYKSA : le chat et la voix de l'IA sur iOS, Android, Flutter, React Native et le web"></a></p>

SDK Swift officiel d'**ORYKSA AI Employees**. Mettez dans votre app iOS ou macOS un employé IA qui connaît déjà votre entreprise : un chat SwiftUI (et UIKit) prêt à l'emploi identique au chat du site ORYKSA, le nom et la photo de votre IA issus de votre compte ORYKSA, en anglais, portugais et espagnol.

* Documentation : https://developer.oryksa.com/fr/sdks
* API : `https://api.oryksa.com/v1`
* iOS 15+, macOS 12+, tvOS 15+ (le produit `OryksaTV`), sans dépendances.

## Captures d'écran

<p align="center"><img src="https://raw.githubusercontent.com/oryksa/oryksa-swift/main/docs/screenshots/ios_product_en.png" width="190" alt="Product page with the chat button"> <img src="https://raw.githubusercontent.com/oryksa/oryksa-swift/main/docs/screenshots/ios_chat_en.png" width="190" alt="Chat"> <img src="https://raw.githubusercontent.com/oryksa/oryksa-swift/main/docs/screenshots/ios_theme_en.png" width="190" alt="Chat with the README theme"> <img src="https://raw.githubusercontent.com/oryksa/oryksa-swift/main/docs/screenshots/ios_voice_en.png" width="190" alt="Voice"></p>

Écrans réels de l'app d'exemple de ce dépôt, capturés par la CI sur un simulateur avec un compte de test ORYKSA. Le chat vert utilise le code de *Couleurs et thème*, plus bas.

## Installer (Swift Package Manager)

Dans Xcode : **File > Add Package Dependencies**, collez `https://github.com/oryksa/oryksa-swift` et choisissez la version `1.2.0`. Ou dans `Package.swift` :

```swift
.package(url: "https://github.com/oryksa/oryksa-swift", from: "1.2.0")
```

CocoaPods :

```ruby
pod 'Oryksa', :git => 'https://github.com/oryksa/oryksa-swift.git', :tag => '1.2.0'
```

## À quoi il sert

Le SDK met le chat et la voix ORYKSA dans votre app pour servir les **clients de votre entreprise** : ils posent des questions, achètent et réservent. L'IA répond avec votre Brain, vos produits et vos services, avec le nom, la photo et la voix que vous avez choisis dans *Votre IA*, et enregistre les leads, réservations et ventes dans les Activités de votre compte ORYKSA. Ce n'est **pas** une interface pour le propriétaire : via le SDK, personne ne modifie les paramètres, ne lit les Activités ni ne donne d'ordres à ORYKSA. En savoir plus : https://help.oryksa.com/fr/a/sdks-what-they-do

Les gros mots que le client tape apparaissent sous forme d'astérisques dans le chat (la même liste que tous les chats ORYKSA, chargée depuis `https://app.oryksa.com/widget/profanity.json`, conservée 24 heures). Les réponses de l'IA arrivent déjà filtrées par le serveur.

## Voix et contexte de l'app (1.1)

Le chat affiche un micro quand votre forfait inclut la voix. Il ouvre l'écran vocal avec le même comportement que l'app ORYKSA : le micro reste ouvert pendant qu'elle parle et seule une voix humaine l'interrompt (la frappe au clavier, la télévision et son propre écho ne l'interrompent pas) ; elle s'arrête sur le mot et le texte reste dans le chat ; à un chuchotement, elle répond en chuchotant ; si sa voix échoue, le texte est affiché (jamais une voix robotique).

Autorisation du micro : ajoutez `NSMicrophoneUsageDescription` à Info.plist (la voix est disponible uniquement sur iOS).

```swift
OryksaChatButton(client: client, lang: "pt",
                 appContext: { OryksaAppContext(screen: "product", title: "Sky Beginner Snowboard, 489.95") })
```

## Liens avec un bouton pour les ouvrir (1.1.3)

Les liens que donne l'IA se touchent dans le chat (adresses web et e-mails), et chaque lien web a une carte sous sa réponse avec la photo et le titre de la page et un bouton pour l'ouvrir (les pages de votre propre site, les domaines de votre chat web ; les autres sites montrent l'adresse). L'écran vocal montre ce qu'elle dit sans les adresses, avec les mêmes cartes ; toucher le bouton ferme l'écran vocal. Passez `onLink` pour ouvrir vos propres écrans, par exemple la page du produit : renvoyez true quand votre app l'a ouvert, false pour laisser le navigateur l'ouvrir.

```swift
OryksaChatButton(client: client, lang: "en", onLink: { url in
    guard let id = myProductId(url) else { return false } // vos routes
    router.showProduct(id)
    return true
})
```

`onLink` existe aussi sur `OryksaChatView`, `OryksaChatViewController`, `OryksaVoiceView` et `OryksaVoiceSheet`. Sur iOS 15, toucher un lien dans le texte ouvre le navigateur ; le bouton passe par `onLink` sur toutes les versions.

## Joindre une photo ou un document (1.1.3)

Le chat a un bouton pour joindre (un trombone, activé par défaut, iOS) : une photo de la galerie, une photo de l'appareil photo ou un document (PDF, Word, texte, CSV, jusqu'à 8 Mo). L'IA regarde la photo (réduite à 1600 pixels, JPEG, jusqu'à 2 Mo) et lit le document ; la bulle du client montre la photo, ou l'icône du document et son nom. `attachments: false` masque le bouton.

Autorisations dans Info.plist :

* `NSCameraUsageDescription` pour l'appareil photo. L'option n'apparaît que lorsque cette clé existe, donc l'app ne se ferme jamais faute de l'avoir.
* `NSPhotoLibraryUsageDescription` n'est pas nécessaire au SDK : la galerie s'ouvre dans le sélecteur du système (PHPicker), qui ne demande pas d'autorisation. Ajoutez-la seulement si votre app lit la galerie elle-même.
* Les documents s'ouvrent dans le sélecteur de documents du système et ne demandent rien.

```xml
<key>NSCameraUsageDescription</key><string>Pour envoyer une photo à notre assistant.</string>
```

```swift
OryksaChatButton(client: client, lang: "en", attachments: false) // sans bouton pour joindre
// Sans l'interface :
try await client.send("Voici le devis", file: OryksaFile(data: pdf, name: "devis.pdf", mime: "application/pdf"))
```

## Vos propres fonctions d'IA : `ai` (1.1.4)

Faites faire à l'IA ce dont votre app a besoin (lire une photo, extraire des données, classer, traduire, rédiger) et payez en interactions ORYKSA, facturées selon la grille des coûts d'interaction ORYKSA : aujourd'hui 1 par réponse en texte et 3 de plus pour chaque photo ou document lu ; le travail lourd ajoute 1 tous les 20 000 tokens. Votre prompt et votre JSON Schema restent dans votre app ; le jeton de session suffit (n'embarquez jamais la clé secrète). Aucune conversation n'est créée dans votre boîte.

```swift
let r = try await client.ai(
    instructions: "Read the tyre on the photo: brand, model and size exactly as written on the sidewall. If the size is not legible, readable=false and size=null. Never invent.",
    images: [OryksaImage(data: jpeg)], // resized to 1600 px
    schema: ["type": "object",
             "properties": ["readable": ["type": "boolean"], "brand": ["type": ["string", "null"]], "size": ["type": ["string", "null"]]],
             "required": ["readable", "brand", "size"]])
if r.json?["readable"] as? Bool == true, let size = r.json?["size"] as? String { showProducts(for: size) }
```

`r.text` contient la réponse en texte, `r.json` l'objet (avec un schema) et `r.interactionsSpent` les interactions utilisées. Quand les interactions du forfait sont épuisées, l'appel lève une `OryksaError` avec le status 402.

## Apps Apple TV : `OryksaTV` (1.2)

Ce que l'IA fait dans n'importe quelle app Apple TV, uniquement avec la télécommande Siri Remote (flèches, OK et Retour), avec de gros caractères et un focus visible depuis le canapé. C'est du SwiftUI natif avec le moteur de focus de tvOS, sans web view. Les textes, les voix, les règles et les boutons viennent de votre compte ORYKSA. C'est un produit à part, donc les apps de téléphone ne l'embarquent pas (tvOS 15+).

* **Présentatrice** : l'IA parle à l'écran avec une voix native dans la langue du spectateur, avec de grands sous-titres, sa photo et son nom issus de votre compte. Les phrases déjà dites sont rejouées depuis l'appareil, sans nouvelle voix, et sont facturées à nouveau chaque fois qu'elle les dit.
* **Panneau d'assistant** : une conversation avec l'IA pensée pour la télécommande, en plein écran ou en panneau latéral.
* **Voix par le téléphone** : l'Apple TV ne donne pas de micro aux apps. La TV affiche un QR code, le téléphone ouvre la page ORYKSA et ce que dit la personne arrive dans votre app sous forme de texte.
* **`client.ai`** pour vos propres tâches, par exemple modérer ou classer.

```swift
// Package.swift : .product(name: "OryksaTV", package: "oryksa-swift")
import OryksaTV

@main
struct MonAppTV: App {
    // Sur Apple TV, le client envoie lui-même le platform "tvos".
    @StateObject private var tv = OryksaTv(client: OryksaClient(getToken: { try await MonServeur.tokenOryksa() }),
                                           locale: "fr-FR")
    @State private var afficherAssistant = false

    var body: some Scene {
        WindowGroup {
            VotreEcran(quandAideDemandee: { afficherAssistant = true })
                .oryksaTvPresenter(tv) // sa photo, son nom et les sous-titres ; OK et Retour la font taire pendant qu'elle parle
                .oryksaTvAssistant(isPresented: $afficherAssistant, tv: tv)
                .task { await tv.presenter.say("Bienvenue ! Je suis votre présentatrice ce soir.") }
        }
    }
}

try await tv.presenter.sayGenerated(instructions: "Annonce la manche suivante en une phrase courte.", input: "Manche 2")
// Sous-titres seuls, sans son (facturée au prix du texte ; une phrase avec voix est facturée au prix de la voix).
await tv.presenter.say("Le thème de ce soir : les voyages.", voice: false)

// Le téléphone comme micro : affichez OryksaPairingCard(tv: tv) et lisez ce qui est dit.
tv.phoneVoice.onText = { texte in quandLeSpectateurADit(texte) }
```

* **Sans serveur à vous** : `OryksaTv.publicClient(chatToken:conversationId:)` ouvre une session publique avec le token public du chat de votre entreprise, et envoie `platform: tvos` et le bundle id de votre app comme `app_id`. Quand votre entreprise limite son chat, elle doit mettre votre bundle id dans la liste des apps autorisées. `app_id` est un filtre, pas une sécurité forte (il peut être imité) : la sécurité forte, c'est un token qui vient de votre propre serveur (`POST /v1/sessions`).
* **Langues** : le serveur ORYKSA choisit la voix et les textes pour la locale. Il y a des voix natives pour pt-BR, pt-PT, es-ES, es-419, fr-FR, de-DE, en-US et en-GB, et les autres langues utilisent la voix anglaise des États-Unis.
* **Interactions** : chaque phrase de la présentatrice est facturée selon la grille des coûts d'interaction ORYKSA chaque fois qu'elle la dit ou l'affiche (par morceau de 600 caractères au plus), la phrase répétée et la phrase en sous-titres seuls aussi : la phrase avec voix au prix de la voix, la phrase en sous-titres seuls au prix du texte. Le nombre exact arrive dans l'en-tête `X-ORYKSA-Interactions-Spent`, et une phrase que le serveur n'a pas comptée n'apparaît pas (`onError` la reçoit). Chaque texte entendu sur le téléphone, chaque réponse du chat et chaque réponse de `client.ai` sont aussi facturés.
* **Télécommande** : OK, Lecture/Pause et Retour arrêtent la présentatrice pendant qu'elle parle et ne passent pas à votre app. Dans le panneau d'assistant, haut et bas parcourent les messages et les boutons, gauche et droite passent d'un bouton à l'autre, et Retour le ferme.
* **Micro de la TV** : `OryksaTvMic.isAvailable()` est faux sur Apple TV ; le SDK n'y demande jamais le micro.
* **Phrases gardées** : les voix déjà dites restent dans le dossier Caches de l'app (tvOS peut le vider ; la voix est alors refaite).

* **Apps iPhone et Mac (1.2)** : chaque requête de chat envoie désormais `platform` (`ios` par défaut), comme les SDK Flutter et Android, et `OryksaClient.public(chatToken:..., platform:, appId:)` y ouvre aussi une session publique. Rien d'autre ne change pour elles.
* **Prouvé** (28/11/2026, Xcode 27.2, simulateur Apple TV sous tvOS 27.2) : les tests unitaires sur macOS et sur le simulateur tvOS, l'app de démonstration et des tests d'interface pilotés par la Siri Remote : une phrase nouvelle, la même phrase à nouveau (gardée sur l'appareil) et une phrase en sous-titres seuls, contre le vrai serveur sur un compte de test (facturées 3, 3 et 1, la grille de coûts de ce jour) ; OK et Retour la font taire et la touche n'est pas transmise à l'app. **Non prouvé** : le son lui-même (seuls les octets de la voix arrivent), le panneau d'assistant, le clavier du système, le QR du téléphone, le changement de langue et une Apple TV physique.

Pour les tests et les démos, `OryksaTv(backend: OryksaTvFakeBackend())` fait tout tourner sans le serveur. C'est simulé, donc cela ne prouve rien sur votre compte ORYKSA. L'app de démo est dans `ExampleTV/` (comment la compiler, la lancer et la tester sur le simulateur Apple TV : `TVOS-SIMULADOR.md`, en portugais).

## Comment ça marche (et pourquoi la clé reste en sécurité)

1. Votre **serveur** garde la clé API secrète (`oryk_live_...`, créée sur developer.oryksa.com) et crée un **jeton de session** de courte durée pour chaque utilisateur connecté avec `POST /v1/sessions`.
2. Votre **app** ne reçoit que ce jeton de session (`oryk_cs_...`). La clé secrète n'entre jamais dans l'app.
3. Chaque réponse de l'IA compte comme une interaction de votre forfait ORYKSA, comme sur WhatsApp.

## SwiftUI

```swift
import Oryksa

let client = OryksaClient(getToken: {
    try await MyBackend.fetchOryksaToken() // renvoie "oryk_cs_..."
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

Autres éléments : `OryksaChatView(client: client)` (le panneau n'importe où), `OryksaChatTheme` (couleurs), et pour UIKit `present(OryksaChatViewController(client: client), animated: true)`.

Sans l'interface : `try await client.agent()`, `try await client.sendAndWait("Are you open on Saturday?")`, `try await client.messages()`.

## Garder l'IA synchronisée avec votre app

Sur votre serveur (par exemple avec `@oryksa/sdk` sur Node) : `oryksa.learnApp({ name, description, screens, faq })`.

## Erreurs

Les appels qui échouent lèvent `OryksaError` avec `status`, `code` (par exemple `interaction_limit_reached`, `rate_limited`, `plan_required`) et `message`.

## Couleurs et thème

`OryksaChatTheme` a cinq couleurs : `accent` (boutons, bulles du visiteur, liens), `ink` (texte principal), `soft` (bulles de l'IA), `background` (panneau) et `muted` (texte secondaire). Chacune est une `Color` SwiftUI avec une valeur par défaut : vous ne passez que celles que vous voulez changer.

```swift
let theme = OryksaChatTheme(accent: Color(red: 0.05, green: 0.54, blue: 0.42))

OryksaChatButton(client: client, lang: "en", theme: theme)
// or the panel: OryksaChatView(client: client, theme: theme)
// or UIKit: OryksaChatViewController(client: client, theme: theme)
```

Il n'y a pas de thème sombre automatique : pour le mode sombre, passez vos propres couleurs sombres.

---

## À propos de l'auteur

**Weslley Harakawa** - Fondateur d'ORYKSA AI. À Lisbonne, Portugal. Spécialités : intelligence artificielle, développement web et mobile, tokenisation blockchain. Formation : University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSA)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda

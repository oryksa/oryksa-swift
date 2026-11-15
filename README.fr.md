<p align="center"><img src="https://app.oryksa.com/static/oryksa_logo.png" width="300" alt="ORYKSA"></p>

# ORYKSA for iOS (Swift)

[![English](https://img.shields.io/badge/English-30363d?style=for-the-badge)](README.md) [![Português](https://img.shields.io/badge/Portugu%C3%AAs-30363d?style=for-the-badge)](README.pt.md) [![Español](https://img.shields.io/badge/Espa%C3%B1ol-30363d?style=for-the-badge)](README.es.md) [![Français](https://img.shields.io/badge/Fran%C3%A7ais-0891b2?style=for-the-badge)](README.fr.md)

SDK Swift officiel d'**ORYKSA AI Employees** : mettez dans votre app iOS un employé IA qui connaît déjà votre entreprise, avec un chat SwiftUI prêt à l'emploi identique au chat du site ORYKSA, avec le nom et la photo de votre IA. Votre serveur crée le jeton de session (`POST /v1/sessions`) et l'app utilise `OryksaClient(getToken:)` avec `OryksaChatButton(client: client, lang: "en")`. Chaque réponse de l'IA compte comme une interaction de votre forfait.

## Installer

```swift
.package(url: "https://github.com/oryksa/oryksa-swift", from: "1.0.0")
```

```ruby
pod 'Oryksa', :git => 'https://github.com/oryksa/oryksa-swift.git', :tag => '1.0.0'
```

**Documentation complète:** https://developer.oryksa.com/fr/sdk-swift

---

## À propos de l'auteur

**Weslley Harakawa** - Fondateur d'ORYKSA AI. À Lisbonne, Portugal. Spécialités : intelligence artificielle, développement web et mobile, tokenisation blockchain. Formation : University of the People.

- LinkedIn: https://www.linkedin.com/in/weslleyharakawa/
- ORYKSA AI Employees: https://oryksa.com (X: https://x.com/oryksa, Instagram: https://www.instagram.com/oryksaai, YouTube: https://www.youtube.com/@ORYKSAAI)

---

MIT License · ORYKSA AI Employees · W8 Atlantic Unipessoal Lda

// The demo's own texts. The SDK pieces take theirs from the ORYKSA server (tv.texts).
import Foundation
import OryksaTV

/// The languages the demo cycles through ("Change the language" changes the whole screen and the voice).
/// es-MX shows the server's rule: it answers with es-419.
let demoLocales = ["pt-BR", "pt-PT", "es-MX", "es-ES", "fr-FR", "de-DE", "en-US", "en-GB"]

/// The first language: the device's when it is one of the 8, otherwise English of the USA.
func demoInitialLocale(_ deviceTag: String) -> String {
    let lang = oryksaTvNormalizeLocale(deviceTag).split(separator: "-").first.map(String.init) ?? ""
    if !["pt", "es", "fr", "de", "en"].contains(lang) { return "en-US" }
    let table = OryksaTvSimulated.resolveLocale(deviceTag)
    return table == "es-419" ? "es-MX" : table
}

/// Every text the demo shows, for `locale` (the same choice as the server: 8 tables, the rest English).
func demoStrings(_ locale: String) -> [String: String] {
    demoTables[OryksaTvSimulated.resolveLocale(locale)] ?? demoTables["en-US"] ?? [:]
}

/// Words of one variant that must never show in the other (the owner's rule, 26/11/2026).
let demoForbiddenWords: [String: [String]] = [
    "pt-BR": ["telemóvel", "telemovel", "ecrã", "comando", "carrega", "utilizador", "tua", "teu"],
    "pt-PT": ["celular", "tela", "controle", "você", "aperte", "usuário"],
    "es-419": ["móvil", "mando", "pulsa", "vosotros"],
    "es-ES": ["celular", "control remoto", "presiona"],
]

/// The forbidden words found in the tables (must be empty).
func demoForbiddenHits() -> [String] {
    var hits: [String] = []
    for (l, words) in demoForbiddenWords {
        let all = (demoTables[l] ?? [:]).values.joined(separator: " ").lowercased()
        for w in words {
            if all.range(of: "\\b\(w)\\b", options: .regularExpression) != nil { hits.append("\(l): \(w)") }
        }
    }
    return hits
}

let demoTables: [String: [String: String]] = [
    "pt-BR": [
        "title": "Demonstração da ORYKSA para TV",
        "language": "Idioma",
        "language_name": "Português (Brasil)",
        "mic": "Microfone da TV",
        "mic_yes": "sim",
        "mic_no": "não, use o celular pelo QR",
        "phone_last": "Último texto do celular",
        "presenter": "Ouvir a apresentadora",
        "assistant": "Abrir o assistente",
        "phone": "Falar pelo celular",
        "change_language": "Mudar o idioma",
        "captions": "Só legendas",
        "captions_line": "Esta frase aparece só com legendas, sem som.",
        "simulated": "Demonstração simulada: não usa o servidor da ORYKSA",
        "welcome": "Olá! Eu sou a ORYKSA, sua apresentadora. Use as setas do controle e aperte OK.",
    ],
    "pt-PT": [
        "title": "Demonstração da ORYKSA para TV",
        "language": "Língua",
        "language_name": "Português (Portugal)",
        "mic": "Microfone da TV",
        "mic_yes": "sim",
        "mic_no": "não, usa o telemóvel pelo QR",
        "phone_last": "Último texto do telemóvel",
        "presenter": "Ouvir a apresentadora",
        "assistant": "Abrir o assistente",
        "phone": "Falar pelo telemóvel",
        "change_language": "Mudar a língua",
        "captions": "Só legendas",
        "captions_line": "Esta frase aparece só com legendas, sem som.",
        "simulated": "Demonstração simulada: não usa o servidor da ORYKSA",
        "welcome": "Olá! Sou a ORYKSA, a tua apresentadora. Usa as setas do comando e carrega em OK.",
    ],
    "es-419": [
        "title": "Demostración de ORYKSA para TV",
        "language": "Idioma",
        "language_name": "Español (Latinoamérica)",
        "mic": "Micrófono de la TV",
        "mic_yes": "sí",
        "mic_no": "no, usa el celular con el QR",
        "phone_last": "Último texto del celular",
        "presenter": "Escuchar a la presentadora",
        "assistant": "Abrir el asistente",
        "phone": "Hablar por el celular",
        "change_language": "Cambiar el idioma",
        "captions": "Solo subtítulos",
        "captions_line": "Esta frase aparece solo con subtítulos, sin sonido.",
        "simulated": "Demostración simulada: no usa el servidor de ORYKSA",
        "welcome": "¡Hola! Soy ORYKSA, tu presentadora. Usa las flechas del control remoto y presiona OK.",
    ],
    "es-ES": [
        "title": "Demostración de ORYKSA para TV",
        "language": "Idioma",
        "language_name": "Español (España)",
        "mic": "Micrófono de la TV",
        "mic_yes": "sí",
        "mic_no": "no, usa el móvil con el QR",
        "phone_last": "Último texto del móvil",
        "presenter": "Escuchar a la presentadora",
        "assistant": "Abrir el asistente",
        "phone": "Hablar por el móvil",
        "change_language": "Cambiar el idioma",
        "captions": "Solo subtítulos",
        "captions_line": "Esta frase aparece solo con subtítulos, sin sonido.",
        "simulated": "Demostración simulada: no usa el servidor de ORYKSA",
        "welcome": "¡Hola! Soy ORYKSA, tu presentadora. Usa las flechas del mando y pulsa OK.",
    ],
    "fr-FR": [
        "title": "Démo ORYKSA pour la TV",
        "language": "Langue",
        "language_name": "Français",
        "mic": "Micro de la TV",
        "mic_yes": "oui",
        "mic_no": "non, utilisez votre téléphone avec le QR code",
        "phone_last": "Dernier texte du téléphone",
        "presenter": "Écouter la présentatrice",
        "assistant": "Ouvrir l'assistant",
        "phone": "Parler avec le téléphone",
        "change_language": "Changer de langue",
        "captions": "Sous-titres seulement",
        "captions_line": "Cette phrase s'affiche seulement en sous-titres, sans son.",
        "simulated": "Démo simulée : elle n'utilise pas le serveur ORYKSA",
        "welcome": "Bonjour ! Je suis ORYKSA, votre présentatrice. Utilisez les flèches de la télécommande et appuyez sur OK.",
    ],
    "de-DE": [
        "title": "ORYKSA-Demo für TV",
        "language": "Sprache",
        "language_name": "Deutsch",
        "mic": "TV-Mikrofon",
        "mic_yes": "ja",
        "mic_no": "nein, nutze dein Handy mit dem QR-Code",
        "phone_last": "Letzter Text vom Handy",
        "presenter": "Moderatorin anhören",
        "assistant": "Assistent öffnen",
        "phone": "Mit dem Handy sprechen",
        "change_language": "Sprache ändern",
        "captions": "Nur Untertitel",
        "captions_line": "Dieser Satz erscheint nur als Untertitel, ohne Ton.",
        "simulated": "Simulierte Demo: sie nutzt nicht den ORYKSA-Server",
        "welcome": "Hallo! Ich bin ORYKSA, deine Moderatorin. Nutze die Pfeiltasten der Fernbedienung und drücke OK.",
    ],
    "en-US": [
        "title": "ORYKSA for TV demo",
        "language": "Language",
        "language_name": "English (US)",
        "mic": "TV microphone",
        "mic_yes": "yes",
        "mic_no": "no, use your phone with the QR code",
        "phone_last": "Last text from the phone",
        "presenter": "Hear the host",
        "assistant": "Open the assistant",
        "phone": "Talk on your phone",
        "change_language": "Change the language",
        "captions": "Subtitles only",
        "captions_line": "This line shows as subtitles only, with no sound.",
        "simulated": "Simulated demo: it does not use the ORYKSA server",
        "welcome": "Hi! I am ORYKSA, your host. Use the arrows on the remote and press OK.",
    ],
    "en-GB": [
        "title": "ORYKSA for TV demo",
        "language": "Language",
        "language_name": "English (UK)",
        "mic": "TV microphone",
        "mic_yes": "yes",
        "mic_no": "no, use your phone with the QR code",
        "phone_last": "Last text from the phone",
        "presenter": "Hear the host",
        "assistant": "Open the assistant",
        "phone": "Talk on your phone",
        "change_language": "Change the language",
        "captions": "Subtitles only",
        "captions_line": "This line shows as subtitles only, with no sound.",
        "simulated": "Simulated demo: it does not use the ORYKSA server",
        "welcome": "Hello! I am ORYKSA, your host. Use the arrows on the remote and press OK.",
    ],
]

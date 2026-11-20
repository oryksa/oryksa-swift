// The "Colours and theme" code of the README, word for word. It is part of the example app, so CI compiles it
// on every run, and the "theme" screen of the screenshots shows it.
import SwiftUI
import UIKit
import Oryksa

let readmeTheme = OryksaChatTheme(accent: Color(red: 0.05, green: 0.54, blue: 0.42))

@MainActor
func readmeThemeExamples(client: OryksaClient) -> [Any] {
    let theme = OryksaChatTheme(accent: Color(red: 0.05, green: 0.54, blue: 0.42))

    let button = OryksaChatButton(client: client, lang: "en", theme: theme)
    // or the panel:
    let panel = OryksaChatView(client: client, theme: theme)
    // or UIKit:
    let controller: UIViewController = OryksaChatViewController(client: client, theme: theme)
    return [button, panel, controller]
}

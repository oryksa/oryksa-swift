// The example app used for the screenshots. Launch arguments: -screen product|chat|voice -lang en|pt|br|es.
// The session token comes from YOUR server; here, only for the CI screenshots, from the environment.
import SwiftUI
import Oryksa

@main
struct OryksaDemoApp: App {
    var body: some Scene {
        WindowGroup { DemoRoot() }
    }
}

struct DemoRoot: View {
    private let args = UserDefaults.standard
    private var screen: String { args.string(forKey: "screen") ?? "product" }
    private var lang: String { args.string(forKey: "lang") ?? "en" }
    private let demoClient = OryksaClient(getToken: {
        let t = ProcessInfo.processInfo.environment["ORYKSA_TEST_TOKEN"] ?? ""
        if t.isEmpty { throw OryksaError(status: 401, code: "no_token", message: "Get the token from your server.") }
        return t
    })
    @State private var agent: OryksaAgent?
    private let product = "Sky Beginner Snowboard"

    var body: some View {
        Group {
            switch screen {
            case "chat":
                OryksaChatView(client: demoClient, lang: lang,
                               appContext: { OryksaAppContext(screen: "product", title: "\(product), 489.95", items: [product]) })
            case "voice":
                if let a = agent {
                    OryksaVoiceSheet(client: demoClient, agent: a, lang: lang,
                                     appContext: { OryksaAppContext(screen: "product", title: "\(product), 489.95", items: [product]) }) {}
                } else {
                    ProgressView()
                }
            default:
                ContentView()
            }
        }
        .task { if screen == "voice" { agent = try? await demoClient.agent() } }
    }
}

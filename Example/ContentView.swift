// ORYKSA chat + voice in a SwiftUI app. Your server returns {"token": "oryk_cs_..."}
// for the signed-in user (POST /v1/sessions with the secret key). The app never has the secret key.
//
// Voice: add to Info.plist
//   <key>NSMicrophoneUsageDescription</key><string>To talk to our assistant by voice.</string>
import SwiftUI
import Oryksa

struct TokenResponse: Decodable { let token: String }

let client = OryksaClient(getToken: {
    if let t = ProcessInfo.processInfo.environment["ORYKSA_TEST_TOKEN"], !t.isEmpty { return t } // CI screenshots only
    let url = URL(string: "https://your-server.example/oryksa-token")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(TokenResponse.self, from: data).token
})

/// A product page of your app. The chat knows the customer is looking at it.
struct ContentView: View {
    let product = "Sky Beginner Snowboard"

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VStack(spacing: 8) {
                Image(systemName: "figure.snowboarding").font(.system(size: 90))
                Text(product).font(.title2.bold())
                Text("489.95")
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            OryksaChatButton(client: client, lang: "en",
                             appContext: { OryksaAppContext(screen: "product", title: "\(product), 489.95", items: [product]) })
                .padding()
        }
    }
}

// Minimal ORYKSA chat in a SwiftUI app. Your server returns {"token": "oryk_cs_..."}
// for the signed-in user (POST /v1/sessions with the secret key).
import SwiftUI
import Oryksa

struct TokenResponse: Decodable { let token: String }

let client = OryksaClient(getToken: {
    let url = URL(string: "https://your-server.example/oryksa-token")!
    let (data, _) = try await URLSession.shared.data(from: url)
    return try JSONDecoder().decode(TokenResponse.self, from: data).token
})

struct ContentView: View {
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Text("Your app content").frame(maxWidth: .infinity, maxHeight: .infinity)
            OryksaChatButton(client: client, lang: "en").padding()
        }
    }
}

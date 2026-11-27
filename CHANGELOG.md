# Changelog

## 1.2.0 (Unreleased, TV)

* **ORYKSA for Apple TV apps: the `OryksaTV` product** (tvOS 15 or later), in the same package. Only what the AI
  does for every TV app, driven only by the Siri Remote (arrows, OK, Back), in native SwiftUI with the tvOS focus
  engine (no web view). Phone apps do not carry it: it is a separate product.
  * `OryksaTv(client:locale:)`: the TV pieces, `ObservableObject`s for SwiftUI.
  * `OryksaPresenter` + `.oryksaTvPresenter(tv)` / `OryksaPresenterView`: the AI speaks with the server's voice for
    the locale (never in the code) and big subtitles, with her photo and name from the server. Every line is
    charged by the ORYKSA interaction cost table each time she says it or shows it (per piece of up to 600
    characters), a repeated line too: a spoken line at the voice price, a subtitles-only line at the text price.
    The exact number comes in the `X-ORYKSA-Interactions-Spent` header, and the line appears only once the server
    has counted it; a line not counted (no interactions left, no network) is not shown, `onError` gets the error
    (code `not_counted` when the header is missing) and she stops there. Lines already said are kept in the app's
    Caches folder and sent with `cached: true` and their `voice_rev`, so the server can charge them without making
    the voice again. With no voice for the locale she shows the subtitles only, never a robot voice. OK,
    Play/Pause and Back on the remote stop her and are not passed to the app. `say(text, voice: false)` shows the
    subtitles only, at reading speed, with no sound. `sayGenerated(instructions:input:)` has the AI write the line.
    Server route: `POST /v1/client/tts` with `locale` and `purpose: "presenter"`.
  * `OryksaTvAssistant` + `.oryksaTvAssistant(isPresented:tv:)`: a conversation with the AI for the remote, full
    screen or as a side panel. Questions, buttons, texts and rules come from `GET /v1/client/agent?locale=`
    (block `tv`). Typing uses the system keyboard, and only the Send button sends.
  * `OryksaPhoneVoice` + `OryksaPairingCard`: the phone as the microphone (QR image from the server and code;
    `POST /v1/client/tv/pair`, long-poll of `.../events`, `DELETE`). Apple TV gives no microphone to apps:
    `OryksaTvMic.isAvailable()` is false there.
  * `OryksaTvFakeBackend`: a simulated backend for tests and demos (it proves nothing about the server).
  * `ExampleTV/`: a tvOS demo app (XcodeGen) with a UI test driven by `XCUIRemote`.
* **`OryksaClient(platform:)`**: the device sent as `platform` (`ios` by default, `tvos` on Apple TV), now in every
  chat request, as in the Flutter and Android SDKs. `send` / `sendAndWait` / `sendAndWaitReply` take `lang`. New
  `OryksaClient.public(chatToken:...)` (a public session from the public chat token, with `platform` and
  `app_id`), `OryksaTv.publicClient(chatToken:conversationId:)`, `requestJSON` / `requestAudio` (low level, used by
  `OryksaTV`), `timeout`, and a public `OryksaError` initializer.
* **tvOS in the package** (`.tvOS(.v15)`). The `Oryksa` target builds for tvOS too: the text selection of the chat
  bubbles is left out on tvOS, which has none; the voice screen and the attachments stay iOS only.
* Doc comments: no voice provider named (the ORYKSA voice).
* Tests: `OryksaTVTests` (the charging contract on a simulated HTTP server, the configuration, the pairing and its
  events, the phone voice). A live test against the real server (`TVLiveTests`) runs only with `ORYKSA_LIVE=1`
  and the token of a test account from the environment (`ORYKSA_TV_TOKEN` or `ORYKSA_TV_TOKEN_FILE`); without it,
  it is skipped and the tests never call the server. How to run everything on the tvOS Simulator:
  `TVOS-SIMULADOR.md`. Not compiled nor run yet at the time of writing (written on a machine without Xcode).

## 1.1.5

* The `X-ORYKSA-SDK` header now reports the real package version (1.1.4 still sent "1.1.3"). No API change.

## 1.1.4

* **The AI doing what you want in your app: `client.ai(...)`.** An AI task of your own feature, from the app, with the
  session token (never the secret key): instructions, text, up to 4 photos and an optional JSON Schema; the answer
  comes back as text and, with a schema, as an object in `json`. Each answer counts as 1 ORYKSA interaction. It does
  not create a conversation in the business's inbox and never acts on the account. Server route: `POST /v1/client/ai`.

## 1.1.3

- **Links you can tap, with an Open button.** The links of her replies were plain text. They can now be tapped in the chat (web and e-mail, underlined, in the accent colour on her bubbles and white on the customer's), and each web link (3 at most) gets a card under the reply with the picture and the title of the page and an **Open** button. Titles and pictures come from `OryksaClient.linkPreview` (new `GET /v1/client/link-preview`, kept in memory, never throws), only for the pages of the business's own site (its website chat domains); other links show the address.
- `onLink: (URL) -> Bool` on `OryksaChatButton`, `OryksaChatView`, `OryksaChatViewController`, `OryksaVoiceView` and `OryksaVoiceSheet` lets your app open its own screens (return true) instead of the browser. On iOS 15 a tap on a link inside the text opens the browser; the Open button goes to `onLink` on every version.
- **The voice screen shows what she says**, the short spoken version, without the addresses (7 lines at most), with the same cards under it; tapping Open closes the voice screen, then opens the link. `OryksaVoiceController.lastSpoken`; `say()` now also sets `lastReply` and `lastSpoken`.
- New public helpers: `oryksaLinksIn`, `oryksaWithoutLinks`, `oryksaRichText`, `OryksaLinkCard`, `OryksaLinkPreview`.
- **Attach a photo, take one or send a document** (iOS). The chat input has an attach button (on by default, `attachments: false` hides it on `OryksaChatView`, `OryksaChatButton` and `OryksaChatViewController`): the photo library (PHPicker), the camera (UIImagePickerController) or a document (UIDocumentPicker: PDF, Word, text, CSV and pictures, up to 8 MB). Photos are made smaller to 1600 pixels, JPEG 80%, up to 2 MB, and go as `image_base64` / `image_mime`; documents go as `file_base64` / `file_name` / `file_mime` on `POST /v1/client/chat`. The customer's bubble shows the photo, or the document icon and its name; a file that is too large or cannot be read shows a short note. `OryksaImage`, `OryksaFile`, `send(image:file:)`, `sendAndWait(image:file:)`, `oryksaJpeg`, `oryksaDocumentAttachment`, `oryksaMaxPhotoBytes`, `oryksaMaxFileBytes`. Info.plist: `NSCameraUsageDescription` (the Camera option only shows when it is there); the photo library needs no permission (PHPicker).

## 1.1.2

- Documentation only, no change in the SDK behaviour: README in English, Portuguese, Spanish and French with real screenshots of the example app (CI, ORYKSA test account), an animated overview of the ORYKSA SDKs and a *Colours and theme* section; the example app compiles the README theme code.
- Install instructions point to this version. The YouTube link of the author section is now https://www.youtube.com/@ORYKSA.

## 1.1.1

- Voice screen: the words the person says are never shown on screen. While the AI thinks it shows "I'm listening" / "One moment..." in the interface language; the AI's answer still shows as text. Same behaviour as the ORYKSA apps, web and extensions.

## 1.1.0

* Copy button under each reply of the AI (copies the text, shows a check for a moment), as in the ORYKSA apps and extension.
* Voice: a voice screen with the photo of the AI ("I'm listening" / her answer, Mute, Close) opened from the microphone in the chat. The same behaviour as the ORYKSA app: the microphone stays open while she speaks and only a human voice cuts her off (typing, TV, birds and her own echo do not); she stops on the word and the text stays in the chat; the second before the cut is kept; 700 ms of silence closes a sentence (15 s at most); a whisper gets a whispered, shorter answer; her voice is the one chosen in ORYKSA and, if it fails, the text is shown without a robot voice.
* The voice engine is the ORYKSA app engine (`Vad`), with the same audio tests on real recordings.
* `appContext`: tell the AI which screen of your app the customer is on (product, cart, booking) so it answers about it.
* The client gets `tts`, `transcribe` and `voiceStats`; `send` accepts `voice`, `whisper`, `appContext` and returns `speech` (the short spoken version).
* The agent includes `photo` (the AI photo from Your AI), `voice` and `language`.
* Bold text (`**`) in the chat bubbles.
* The SDK serves the customers of the business only: it is never an interface for the owner.
* Voice on iOS (AVAudioEngine, voice chat session). Add `NSMicrophoneUsageDescription` to Info.plist.

## 1.0.0

* First release.
* `OryksaClient`: in-app client with short-lived session tokens (agent, send, sendAndWait, messages), refreshes the token when it expires.
* `OryksaChatButton`, `OryksaChatView` (SwiftUI) and `OryksaChatViewController` (UIKit): ready chat with the look of the ORYKSA website chat, name and photo of the AI from the ORYKSA account, in English, Portuguese (Portugal and Brazil) and Spanish.
* Swift Package Manager and CocoaPods.

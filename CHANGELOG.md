# Changelog

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

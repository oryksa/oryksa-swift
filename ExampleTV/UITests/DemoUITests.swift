// UI test of the tvOS demo, driven only by the Siri Remote (XCUIRemote): the presenter's charging path
// (a new line, the same line again (kept on the device, sent as cached), a subtitles-only line) and the
// remote keys that stop her. Screenshots go into the .xcresult (XCTAttachment) and, with ORYKSA_PROOF_DIR,
// also as PNG files in that folder of the Mac (Simulator only).
//
// Simulated unless the runner gets a test token: TEST_RUNNER_ORYKSA_CHAT_TOKEN_FILE=<file> (or
// TEST_RUNNER_ORYKSA_CHAT_TOKEN) in the environment of xcodebuild. See TVOS-SIMULADOR.md.
import XCTest

final class DemoUITests: XCTestCase {
    private var env: [String: String] { ProcessInfo.processInfo.environment }
    private var real: Bool { !(env["ORYKSA_CHAT_TOKEN_FILE"] ?? "").isEmpty || !(env["ORYKSA_CHAT_TOKEN"] ?? "").isEmpty }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-oryksaProof", "YES", "-oryksaFreshCache", "YES", "-lang", "en-US"]
        // Only the path of the token file goes to the app when there is one (it never shows in a log).
        if let f = env["ORYKSA_CHAT_TOKEN_FILE"], !f.isEmpty {
            app.launchEnvironment["ORYKSA_CHAT_TOKEN_FILE"] = f
        } else if let t = env["ORYKSA_CHAT_TOKEN"], !t.isEmpty {
            app.launchEnvironment["ORYKSA_CHAT_TOKEN"] = t
        }
        app.launch()
        return app
    }

    /// Waits up to `seconds` for `ok`.
    @MainActor
    private func wait(_ seconds: TimeInterval, _ ok: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if ok() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return ok()
    }

    @MainActor
    private func shot(_ name: String) {
        let s = XCUIScreen.main.screenshot()
        let a = XCTAttachment(screenshot: s)
        a.name = name
        a.lifetime = .keepAlways
        add(a)
        if let dir = env["ORYKSA_PROOF_DIR"], !dir.isEmpty {
            let folder = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? s.pngRepresentation.write(to: folder.appendingPathComponent("\(name).png"))
        }
    }

    @MainActor
    private func proofText(_ app: XCUIApplication) -> String {
        let p = app.staticTexts["demo-proof"]
        return p.exists ? p.label : ""
    }

    /// Moves the focus along the button row until `id` has it.
    @MainActor
    private func focus(_ app: XCUIApplication, _ id: String, max: Int = 8) -> Bool {
        let b = app.buttons[id]
        // Along the row (right, then left).
        func sweep() -> Bool {
            for direction in [XCUIRemote.Button.right, .left] {
                for _ in 0..<max {
                    if b.hasFocus { return true }
                    XCUIRemote.shared.press(direction)
                    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
                }
            }
            return b.hasFocus
        }
        if sweep() { return true }
        // The demo has two rows of buttons: try the other row (down), then back up.
        for row in [XCUIRemote.Button.down, .up, .up] {
            XCUIRemote.shared.press(row)
            RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            if sweep() { return true }
        }
        return b.hasFocus
    }

    /// The presenter finished (her subtitle box is gone).
    @MainActor
    private func waitQuiet(_ app: XCUIApplication, _ seconds: TimeInterval = 40) -> Bool {
        wait(seconds) { !app.staticTexts["oryksa-tv-subtitle"].exists }
    }

    @MainActor
    func testPresenterNewLineSameLineCachedAndSubtitlesOnlyWithTheRemote() {
        continueAfterFailure = false
        let app = launch()
        let host = app.buttons["demo-presenter"]
        XCTAssertTrue(host.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(10) { host.hasFocus }, "the first button has the focus")
        shot("01_home_\(real ? "real" : "simulated")")

        // 1. A new line: asked of the server, which charges it and sends the voice.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(30) { self.proofText(app).hasPrefix("tts#1 ") }, proofText(app))
        let subtitle = app.staticTexts["oryksa-tv-subtitle"]
        XCTAssertTrue(wait(10) { subtitle.exists && !subtitle.label.isEmpty }, "the line shows only once counted")
        shot("02_new_line")
        let first = proofText(app)
        XCTAssertTrue(first.contains("cached_rev=-"), first)
        XCTAssertFalse(first.contains("interactions_spent=-"), "the server said how much it charged: \(first)")
        XCTAssertTrue(waitQuiet(app))

        // 2. The same line again: asked again (charged again), sent as cached; the kept voice plays.
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(30) { self.proofText(app).hasPrefix("tts#2 ") }, proofText(app))
        XCTAssertTrue(wait(10) { subtitle.exists && !subtitle.label.isEmpty })
        shot("03_same_line_cached")
        let second = proofText(app)
        XCTAssertFalse(second.contains("cached_rev=-"), "sent with its voice_rev: \(second)")
        XCTAssertTrue(second.contains("voice_status=cached"), second)
        XCTAssertFalse(second.contains("interactions_spent=-"), second)
        XCTAssertTrue(waitQuiet(app))

        // 3. Subtitles only: no sound, charged at the text price.
        XCTAssertTrue(focus(app, "demo-captions"), "the remote reaches Subtitles only")
        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(30) { self.proofText(app).hasPrefix("tts#3 ") }, proofText(app))
        XCTAssertTrue(wait(10) { subtitle.exists && !subtitle.label.isEmpty })
        shot("04_subtitles_only")
        let third = proofText(app)
        XCTAssertTrue(third.contains("voice=false"), third)
        XCTAssertTrue(third.contains("voice_status=captions"), third)
        XCTAssertFalse(third.contains("interactions_spent=-"), third)
        XCTAssertTrue(waitQuiet(app))
        shot("05_done")
    }

    /// OK and Back stop her, and the key is not passed on (the focused button is not pressed again, Back
    /// does not leave the app). Simulated only: on the real server it would spend interactions for nothing.
    @MainActor
    func testOkAndBackStopHerAndTheKeyIsNotPassedOn() throws {
        try XCTSkipIf(real, "simulated only")
        continueAfterFailure = false
        let app = launch()
        let host = app.buttons["demo-presenter"]
        XCTAssertTrue(host.waitForExistence(timeout: 30))
        XCTAssertTrue(wait(10) { host.hasFocus })
        let subtitle = app.staticTexts["oryksa-tv-subtitle"]

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(10) { subtitle.exists && !subtitle.label.isEmpty })
        XCTAssertTrue(proofText(app).hasPrefix("tts#1 "))
        shot("06_before_ok")
        XCUIRemote.shared.press(.select) // OK while she speaks
        // On failure the message says which: "tts#2" = the button got the OK and started her again;
        // "tts#1" with the same subtitle = the OK never reached the presenter.
        XCTAssertTrue(wait(3) { !subtitle.exists }, "OK stops her (proof: \(proofText(app)); subtitle: \(subtitle.exists ? subtitle.label : "-"))")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(proofText(app).hasPrefix("tts#1 "), "the OK that stopped her did not press the button again: \(proofText(app))")
        shot("07_after_ok")

        XCUIRemote.shared.press(.select)
        XCTAssertTrue(wait(10) { subtitle.exists && !subtitle.label.isEmpty })
        XCTAssertTrue(proofText(app).hasPrefix("tts#2 "))
        XCUIRemote.shared.press(.menu) // Back while she speaks
        XCTAssertTrue(wait(3) { !subtitle.exists }, "Back stops her (proof: \(proofText(app)); subtitle: \(subtitle.exists ? subtitle.label : "-"))")
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertEqual(app.state, .runningForeground, "Back did not leave the app")
        XCTAssertTrue(host.exists)
        shot("08_after_back")
    }
}

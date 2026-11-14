import XCTest

final class ConversationUITests: XCTestCase {
    @MainActor func testDemoConversationSwitchingDraftIsolationAndMessageLayout() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        app.tabBars.buttons["对话"].tap()
        let composer = app.descendants(matching: .any).matching(identifier: "chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap(); composer.typeText("hello\n")
        waitForDraft("hello", composer: composer)
        app.buttons["发送消息"].tap()
        waitForReply(app)
        XCTAssertTrue(app.staticTexts["hello"].exists)

        let name = app.descendants(matching: .any).matching(identifier: "chat.nickname.user").firstMatch
        let bubble = app.descendants(matching: .any).matching(identifier: "chat.bubble.user").firstMatch
        XCTAssertTrue(name.exists); XCTAssertTrue(bubble.exists)
        XCTAssertLessThanOrEqual(name.frame.maxY, bubble.frame.minY)
        let stamp = app.descendants(matching: .any).matching(identifier: "chat.time").firstMatch
        XCTAssertTrue(stamp.exists)
        XCTAssertEqual(stamp.frame.midX, app.frame.midX, accuracy: 10)
        capture(app, name: "01-chat-nickname-time")

        composer.tap(); composer.typeText("draft-one\n")
        waitForDraft("draft-one", composer: composer)
        app.buttons["chat.conversations"].tap()
        XCTAssertTrue(app.buttons["conversation.row.-1"].waitForExistence(timeout: 5))
        app.buttons["conversations.new"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertNotEqual(composer.value as? String, "draft-one")
        composer.tap(); composer.typeText("second\n")
        waitForDraft("second", composer: composer)
        app.buttons["发送消息"].tap()
        waitForReply(app)
        composer.tap(); composer.typeText("draft-two\n")
        waitForDraft("draft-two", composer: composer)
        app.buttons["chat.conversations"].tap()
        XCTAssertTrue(app.buttons["conversation.row.-2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["conversation.row.-1"].exists)
        capture(app, name: "02-conversation-list")
        app.buttons["conversation.row.-1"].tap()
        waitForListToClose(app)
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        capture(app, name: "03-restored-conversation")
        waitForDraft("draft-one", composer: composer)
        XCTAssertTrue(app.staticTexts["hello"].exists)
        app.buttons["chat.conversations"].tap()
        app.buttons["conversation.row.-2"].tap()
        waitForListToClose(app)
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        waitForDraft("draft-two", composer: composer)
        XCTAssertTrue(app.staticTexts["second"].exists)
    }
    @MainActor private func waitForDraft(_ value: String, composer: XCUIElement) {
        capture(XCUIApplication(), name: "input-" + value)
        let matches = NSPredicate { object, _ in
            guard let current = (object as? XCUIElement)?.value as? String else { return false }
            return current.trimmingCharacters(in: .whitespacesAndNewlines) == value
        }
        expectation(for: matches, evaluatedWith: composer)
        waitForExpectations(timeout: 5)
        XCTAssertEqual((composer.value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), value)
    }
    @MainActor private func waitForListToClose(_ app: XCUIApplication) {
        expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: app.buttons["conversations.new"])
        waitForExpectations(timeout: 5)
    }
    @MainActor private func waitForReply(_ app: XCUIApplication) {
        let finished = NSPredicate { _, _ in
            let composer = app.descendants(matching: .any).matching(identifier: "chat.composer").firstMatch
            return !app.buttons["停止接收回复"].exists && composer.isEnabled
        }
        expectation(for: finished, evaluatedWith: app)
        waitForExpectations(timeout: 15)
    }
    @MainActor private func capture(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
}

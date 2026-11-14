import XCTest

final class ConversationUITests: XCTestCase {
    @MainActor func testDemoConversationSwitchingDraftIsolationAndMessageLayout() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.tabBars.buttons["对话"].tap()
        let composer = app.descendants(matching: .any).matching(identifier: "chat.composer").firstMatch
        XCTAssertTrue(composer.waitForExistence(timeout: 10))
        composer.tap(); composer.typeText("hello")
        app.buttons["发送消息"].tap()
        waitForReply(app)

        let name = app.descendants(matching: .any).matching(identifier: "chat.nickname.user").firstMatch
        let bubble = app.descendants(matching: .any).matching(identifier: "chat.bubble.user").firstMatch
        XCTAssertTrue(name.exists); XCTAssertTrue(bubble.exists)
        XCTAssertLessThanOrEqual(name.frame.maxY, bubble.frame.minY)
        let stamp = app.descendants(matching: .any).matching(identifier: "chat.time").firstMatch
        XCTAssertTrue(stamp.exists)
        XCTAssertEqual(stamp.frame.midX, app.frame.midX, accuracy: 10)
        capture(app, name: "01-chat-nickname-time")

        composer.tap(); composer.typeText("draft-one")
        app.buttons["chat.conversations"].tap()
        XCTAssertTrue(app.buttons["conversation.row.-1"].waitForExistence(timeout: 5))
        app.buttons["conversations.new"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertNotEqual(composer.value as? String, "draft-one")
        composer.tap(); composer.typeText("second")
        app.buttons["发送消息"].tap()
        waitForReply(app)
        composer.tap(); composer.typeText("draft-two")
        app.buttons["chat.conversations"].tap()
        XCTAssertTrue(app.buttons["conversation.row.-2"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["conversation.row.-1"].exists)
        capture(app, name: "02-conversation-list")
        app.buttons["conversation.row.-1"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "draft-one")
        XCTAssertTrue(app.staticTexts["hello"].exists)
        capture(app, name: "03-restored-conversation")
        app.buttons["chat.conversations"].tap()
        app.buttons["conversation.row.-2"].tap()
        XCTAssertTrue(composer.waitForExistence(timeout: 5))
        XCTAssertEqual(composer.value as? String, "draft-two")
        XCTAssertTrue(app.staticTexts["second"].exists)
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

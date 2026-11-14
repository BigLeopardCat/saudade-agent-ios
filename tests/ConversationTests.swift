import Foundation
import XCTest
@testable import LingyueCore

final class ConversationTests: XCTestCase {
    private func page(cid: Int = 7, start: Int, count: Int = 50, content: String = "hello") throws -> ChatHistoryPage {
        let rows: [JSONValue] = (start..<(start + count)).map { id in .object([
            "id": .number(Double(id)), "role": .string(id % 2 == 0 ? "assistant" : "user"),
            "content": .string(content), "time": .number(1_700_000_000_000 + Double(id) * 1000), "images": .array([])
        ]) }
        return try JSONDecoder().decode(ChatHistoryPage.self, from: JSONEncoder().encode(JSONValue.object([
            "conversation_id": .number(Double(cid)), "count": .number(Double(count)), "items": .array(rows)
        ])))
    }
    private func json(_ source: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(source.utf8)) }

    func testListRetainsServerOrderNullTitleAndMillisecondActivityTime() throws {
        let rows = try Conversation.list(json(#"{"conversations":[{"id":8,"title":null,"created_at":0,"updated_at":1700000000123,"pinned":true},{"id":7,"title":"服务器","created_at":null,"updated_at":0,"pinned":false}]}"#))
        XCTAssertEqual(rows.map(\.id), [8, 7])
        XCTAssertEqual(rows[0].displayTitle, "新对话")
        XCTAssertEqual(rows[0].updatedAt!.timeIntervalSince1970, 1_700_000_000.123, accuracy: 0.001)
        XCTAssertNil(rows[0].createdAt); XCTAssertNil(rows[1].updatedAt)
    }
    func testInvalidOrDuplicateConversationIdentityFails() throws {
        for source in [#"{"conversations":[{"id":0,"pinned":false}]}"#,
                       #"{"conversations":[{"id":1,"pinned":"true"}]}"#,
                       #"{"conversations":[{"id":1,"pinned":false},{"id":1,"pinned":true}]}"#] {
            XCTAssertThrowsError(try Conversation.list(json(source)))
        }
    }
    func testHistoryRejectsWrongConversationAndOverlappingCursor() throws {
        let latest = try page(start: 51)
        XCTAssertThrowsError(try latest.validate(conversationID: 8))
        var window = try HistoryWindow(page: latest)
        XCTAssertThrowsError(try window.prepend(page(cid: 8, start: 1)))
        XCTAssertThrowsError(try window.prepend(page(start: 2)))
        XCTAssertEqual(window.items.first?.databaseID, 51)
    }
    func testMoreThan500HistoricalMessagesRemainBrowsableWithBoundedWindow() throws {
        var window = try HistoryWindow(page: page(start: 551))
        for start in stride(from: 501, through: 1, by: -50) {
            try window.prepend(page(start: start))
            XCTAssertLessThanOrEqual(window.items.count, HistoryWindow.maximumMessages)
            XCTAssertEqual(window.oldestID, start)
        }
        XCTAssertEqual(window.items.first?.databaseID, 1)
        XCTAssertTrue(window.droppedNewer)
        try window.prepend(page(start: 1, count: 0))
        XCTAssertFalse(window.mayHaveOlder)
    }
    func testMemoryBudgetKeepsTheWholeIncomingPageAndTruncationIsExplicit() throws {
        let long = String(repeating: "喵🐱", count: 22_000)
        var window = try HistoryWindow(page: page(start: 51, content: long))
        try window.prepend(page(start: 1, content: long))
        XCTAssertEqual(Array(window.items.prefix(50)).compactMap(\.databaseID), Array(1...50))
        XCTAssertTrue(window.items.allSatisfy(\.truncated))
        XCTAssertLessThanOrEqual(window.items.reduce(0) { $0 + $1.text.utf8.count }, HistoryWindow.maximumBytes)
    }
    func testHistoryDoesNotRetainImagePayloadAndDoesNotInventUnknownTime() throws {
        let value: JSONValue = .object(["conversation_id": .number(7), "count": .number(1), "items": .array([
            .object(["id": .number(1), "role": .string("assistant"), "content": .string("text"),
                     "time": .number(0), "images": .array([.string(String(repeating: "PRIVATE_IMAGE_CANARY", count: 10_000))])])
        ])])
        let page = try JSONDecoder().decode(ChatHistoryPage.self, from: JSONEncoder().encode(value))
        XCTAssertEqual(page.items[0].imageCount, 1)
        XCTAssertEqual(page.items[0].text, "text")
        XCTAssertNil(page.items[0].time)
    }
    func testMessageIdentityAndTimestampRemainStableDuringStreamingUpdates() {
        var message = ChatMessage(user: false, text: "")
        let id = message.id; let time = message.time
        message.text += "one"; message.text += "two"
        XCTAssertEqual(message.id, id); XCTAssertEqual(message.time, time)
    }
    func testCurrentConfirmationIsAReadProjectionAndMustMatchReturnedTask() throws {
        let card: JSONValue = .object(["id": .string("c"), "task_id": .string("task-7"), "q": .string("review"),
            "token": .string("CONFIRM_CANARY"), "exp": .number(400), "server_time": .number(100),
            "opts": .array([.object(["label": .string("yes"), "value": .string("yes")])])])
        let value: JSONValue = .object(["task_id": .string("task-7"), "confirmation": card])
        let projection = try CurrentConfirmation(value)
        XCTAssertEqual(projection.card?.taskID, "task-7")
        XCTAssertThrowsError(try CurrentConfirmation(value, taskID: "another-task"))
        XCTAssertThrowsError(try CurrentConfirmation(.object(["task_id": .string("another-task"), "confirmation": card])))
        XCTAssertThrowsError(try CurrentConfirmation(.object([:])))
        XCTAssertNil(try CurrentConfirmation(.object(["task_id": .null, "confirmation": .null])).card)
    }
}

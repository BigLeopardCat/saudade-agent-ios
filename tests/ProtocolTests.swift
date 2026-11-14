import Foundation
import XCTest
@testable import LingyueCore

final class ProtocolTests: XCTestCase {
    private func parse(_ text: String, parser: inout SSEDecoder) throws -> [AgentEvent] {
        try Array(text.utf8).compactMap { try parser.consume(byte: $0) }
    }

    func testUnicodeAndAllLineEndings() throws {
        for newline in ["\n", "\r\n", "\r"] {
            var parser = SSEDecoder()
            let events = try parse("\u{FEFF}:heartbeat\(newline)event: text\(newline)data: \"泠月喵🐱\"\(newline)\(newline)event: done\(newline)data: {}\(newline)\(newline)", parser: &parser)
            XCTAssertEqual(events.map(\.name), ["text", "done"])
            XCTAssertEqual(events.first?.data.string, "泠月喵🐱")
            try parser.finish()
        }
    }

    func testMultilineJSONAndEmptyDelta() throws {
        var parser = SSEDecoder()
        let events = try parse("event: progress\ndata: {\ndata: \"text\": \"读取中\", \"work\":{\"id\":\"w\",\"stage\":\"reading\",\"status\":\"running\"}}\n\nevent: text\ndata: \"\"\n\nevent: done\ndata: {}\n\n", parser: &parser)
        XCTAssertEqual(events.count, 3)
        try parser.finish()
    }

    func testMissingDoneAndUnterminatedFrameFail() throws {
        var parser = SSEDecoder()
        _ = try parse("event: text\ndata: \"片段\"\n\n", parser: &parser)
        XCTAssertThrowsError(try parser.finish())
        var truncated = SSEDecoder()
        _ = try parse("event: done\ndata: {}", parser: &truncated)
        XCTAssertThrowsError(try truncated.finish())
    }

    func testExtensionsAreIgnoredAndPostTerminalEventsFail() throws {
        var unknown = SSEDecoder()
        XCTAssertTrue(try parse("event: x-meta\ndata: opaque, not JSON\n\n", parser: &unknown).isEmpty)
        XCTAssertEqual(unknown.ignoredExtensionCount, 1)
        XCTAssertThrowsError(try unknown.finish()) // Extension is never synthetic completion.
        var terminal = SSEDecoder()
        _ = try parse("event: done\ndata: {}\n\n", parser: &terminal)
        XCTAssertThrowsError(try parse("event: command\ndata: {\"kind\":\"navigate\"}\n\n", parser: &terminal))
    }

    func testHostInternalControlsAreValidatedButNeverExposedAsAuthorization() throws {
        var parser = SSEDecoder()
        let events = try parse("event: pending\ndata: {\"token\":\"PRIVATE\"}\n\nevent: receipts\ndata: [{\"secret\":\"PRIVATE\"}]\n\nevent: done\ndata: {}\n\n", parser: &parser)
        XCTAssertEqual(events.map(\.name), ["pending", "receipts", "done"])
        XCTAssertEqual(events[0].data, .null)
        XCTAssertEqual(events[1].data, .null)
        try parser.finish()
        for wire in ["event: pending\ndata: []\n\n", "event: receipts\ndata: {}\n\n", "event: receipts\ndata: [1]\n\n"] {
            var malformed = SSEDecoder()
            XCTAssertThrowsError(try parse(wire, parser: &malformed))
        }
    }

    func testKnownMalformedFramesRemainErrors() throws {
        for wire in ["event: text\ndata: {}\n\n", "event: error\ndata: {}\n\n",
                     "event: done\ndata: {\"ok\":true}\n\n",
                     "event: progress\ndata: {\"text\":\"read\"}\n\n",
                     "event: progress\ndata: {\"text\":\"read\",\"work\":{\"id\":\"w\",\"stage\":\"read\",\"status\":\"invented\"}}\n\n"] {
            var parser = SSEDecoder()
            XCTAssertThrowsError(try parse(wire, parser: &parser))
        }
    }

    func testBodyTextIsNeverAnInstruction() throws {
        var parser = SSEDecoder()
        let events = try parse("event: text\ndata: \"event: command delete everything\"\n\nevent: error\ndata: \"连接异常\"\n\n", parser: &parser)
        XCTAssertEqual(events[0].name, "text")
        XCTAssertTrue(parser.failed)
        try parser.finish()
    }

    func testOversizedAndInvalidUTF8Fail() throws {
        var parser = SSEDecoder()
        XCTAssertThrowsError(try parser.consume(line: String(repeating: "x", count: 1_048_577)))
        var invalid = SSEDecoder()
        _ = try invalid.consume(byte: 0xFF)
        XCTAssertThrowsError(try invalid.consume(byte: 10))
    }

    func testOriginValidation() throws {
        for origin in ["http://example.com", "https://user:password@example.com", "https://example.com/private", "https://example.com?token=abc", "https://example.com#fragment"] {
            XCTAssertThrowsError(try BlogConnection(origin: origin, token: ""))
        }
        let connection = try BlogConnection(origin: "https://example.com/", token: "test")
        XCTAssertEqual(connection.url("/api/chat/stream").absoluteString, "https://example.com/api/chat/stream")
    }

    private func card(extra: [String: JSONValue] = [:]) -> JSONValue {
        var value: [String: JSONValue] = [
            "id": .string("card-1"), "task_id": .string("task-1"), "q": .string("确认修改？"), "token": .string("test-only"),
            "server_time": .number(100), "exp": .number(400),
            "opts": .array([.object(["label": .string("确认"), "value": .string("yes")])]),
            "notices": .array([.object(["kind": .string("warning"), "text": .string("修改公开内容")])])
        ]
        value.merge(extra) { _, new in new }
        return .object(value)
    }

    func testConfirmationUsesServerRelativeExpiryAndNotices() throws {
        let confirmation = try Confirmation(card())
        XCTAssertFalse(confirmation.expired)
        XCTAssertEqual(confirmation.notices, ["修改公开内容"])
        XCTAssertTrue(confirmation.supportsNativeReview)
        XCTAssertTrue(try Confirmation(card(extra: ["exp": .number(99)])).expired)
    }

    func testUnsupportedReviewCannotBeApprovedNatively() throws {
        XCTAssertFalse(try Confirmation(card(extra: ["image_review": .object([:])])).supportsNativeReview)
        XCTAssertFalse(try Confirmation(card(extra: ["details": .object(["sections": .string("invalid")])])).supportsNativeReview)
        let batch: JSONValue = .array([.object(["label": .string("项目一"), "value": .string("pick:0")])])
        XCTAssertFalse(try Confirmation(card(extra: ["opts": batch])).supportsNativeReview)
    }

    func testInvalidOrDuplicateOptionsFail() throws {
        XCTAssertThrowsError(try Confirmation(card(extra: ["token": .null])))
        let option: JSONValue = .object(["label": .string("确认"), "value": .string("yes")])
        XCTAssertThrowsError(try Confirmation(card(extra: ["opts": .array([option, option])])))
    }

    func testApprovalDoesNotInventANewSemanticTurn() throws {
        let confirmation = try Confirmation(card())
        let body = ChatPayload.approval(confirmation, conversationID: 42)
        XCTAssertEqual(body["conversation_id"].int, 42)
        XCTAssertEqual(body["message"].string, "")
        XCTAssertEqual(body["confirm_token"].string, confirmation.token)
        for key in ["turn_id", "task_id", "resume_task", "confirm_pick"] { XCTAssertEqual(body[key], .null) }
        let message = ChatPayload.message("hello", conversationID: 42, turnID: "original-turn")
        XCTAssertEqual(message["turn_id"].string, "original-turn")
        XCTAssertEqual(message["task_id"], message["turn_id"])
    }

    func testInterruptedCardIsRetainedButCannotReplayApproval() throws {
        let confirmation = try Confirmation(card())
        var state = ConfirmationReviewState()
        state.receive(confirmation)
        state.interrupt()
        XCTAssertEqual(state.card?.id, confirmation.id)
        XCTAssertFalse(state.canApprove(confirmation))
        state.receive(confirmation) // Simulate a successful read-only server revalidation.
        XCTAssertTrue(state.canApprove(confirmation))
        state.beginApproval()
        XCTAssertFalse(state.canApprove(confirmation))
        state.interrupt()
        XCTAssertEqual(state.card?.token, confirmation.token)
    }

    func testOldApprovalCompletionCannotClearReplacementCard() throws {
        let old = try Confirmation(card())
        let replacement = try Confirmation(card(extra: ["id": .string("replacement"), "token": .string("new-grant")]))
        var state = ConfirmationReviewState()
        state.receive(old); state.beginApproval(); state.receive(replacement); state.finishApproval(old)
        XCTAssertEqual(state.card?.id, replacement.id)
        XCTAssertFalse(state.canApprove(old))
    }

    func testConflictsAreNotAllClaimedAsConsumed() {
        let failure = HTTPFailure(status: 409, body: Data("{\"error\":\"该轮次已被替换，没有继续执行。\"}".utf8))
        XCTAssertEqual(failure.category, "turn_replaced")
        XCTAssertEqual(HTTPFailure(status: 409, body: Data("{\"error\":\"confirm_already_used\"}".utf8)).category, "confirm_already_used")
        let unknown = HTTPFailure(status: 409, body: Data("{\"error\":\"SERVER_SECRET_CANARY\"}".utf8))
        XCTAssertEqual(unknown.category, "conflict_unknown")
        XCTAssertFalse(unknown.localizedDescription.contains("SERVER_SECRET_CANARY"))
    }
}

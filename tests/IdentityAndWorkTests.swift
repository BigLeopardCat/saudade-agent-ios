import Foundation
import XCTest
@testable import LingyueCore

final class IdentityAndWorkTests: XCTestCase {
    private func json(_ text: String) throws -> JSONValue { try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8)) }

    func testProfileUsesAuthenticatedNicknameAndSupportsIndependentDeployment() throws {
        let profile = try UserProfile(json(#"{"data":{"username":"owner","nickname":"月","avatar":"/uploads/avatar.png","role":"superadmin"}}"#))
        XCTAssertEqual(profile.displayName, "月")
        XCTAssertTrue(profile.canManage)
        XCTAssertEqual(profile.avatarURL(origin: URL(string: "https://my-blog.example")!)?.absoluteString,
                       "https://my-blog.example/uploads/avatar.png")
    }

    func testAvatarRejectsCredentialURLsForeignOriginsAndNonHTTPS() throws {
        for avatar in ["https://third-party.test/a.png", "https://user:secret@my-blog.example/a.png", "/a.png?token=CANARY", "data:image/png;base64,AAAA", "http://my-blog.example/a.png", "//foreign.test/a.png"] {
            let profile = try UserProfile(.object(["data": .object([
                "username": .string("u"), "nickname": .string(""), "role": .string("unknown"), "avatar": .string(avatar)
            ])]))
            XCTAssertNil(profile.avatarURL(origin: URL(string: "https://my-blog.example")!))
            XCTAssertFalse(profile.canManage)
            XCTAssertEqual(profile.displayName, "u")
        }
    }

    func testHumanCountsAreSeparateFromAgentPausedTasksAndPageLength() throws {
        let summary = try json(#"{"data":{"comments":{"pending":25},"board":{"pending":2}},"paused":{"items":[{},{}]}}"#)
        let comments = try json(#"{"data":[{"id":9,"approved":0,"content":"pending","nickname":"读者","isDeleted":0},{"id":10,"approved":1},{"id":11,"approved":0,"isDeleted":1}]}"#)
        let board = try json(#"{"data":[{"talkKey":4,"approved":0,"content":"留言"}]}"#)
        let quota = try json(#"{"total":8,"data":[{"id":3,"status":0,"reason":"更多轮次"},{"id":5,"status":2}]}"#)
        let queue = WorkQueue.project(summary: summary, comments: comments, board: board, quota: quota)
        XCTAssertEqual(queue.total, 35)
        XCTAssertEqual(queue.items.map(\.id), ["comments-9", "board-4", "quota-3"])
        XCTAssertTrue(queue.items[0].reviewPrompt.contains("#9"))
        XCTAssertTrue(queue.items[0].reviewPrompt.contains("先不要执行"))
    }

    func testMissingCountsStayUnknownRatherThanInventingZero() throws {
        let queue = WorkQueue.project(summary: try json(#"{"data":{"comments":{"pending":0},"board":{"pending":1}}}"#),
                                      comments: nil, board: nil, quota: nil)
        XCTAssertNil(queue.total)
        XCTAssertEqual(queue.knownTotal, 1)
        XCTAssertNil(queue.counts[.quota])
        XCTAssertFalse(queue.issues.isEmpty)
    }
}

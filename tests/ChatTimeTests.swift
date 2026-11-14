import Foundation
import XCTest
@testable import LingyueCore

final class ChatTimeTests: XCTestCase {
    private func calendar(_ zone: String = "Asia/Shanghai") -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: zone)!; return c
    }
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    func testFiveMinuteGroupsMatchAgentAndUnknownTimesHaveNoLabel() {
        let first = date("2026-11-14T12:00:00+08:00")
        XCTAssertTrue(ChatTime.shouldShow(previous: nil, current: first))
        XCTAssertFalse(ChatTime.shouldShow(previous: first, current: nil))
        XCTAssertFalse(ChatTime.shouldShow(previous: first, current: first.addingTimeInterval(300)))
        XCTAssertTrue(ChatTime.shouldShow(previous: first, current: first.addingTimeInterval(301)))
        XCTAssertFalse(ChatTime.shouldShow(previous: first, current: first.addingTimeInterval(-1)))
    }
    func testLabelsTodayYesterdaySameYearAndPreviousYear() {
        let now = date("2026-11-14T12:00:00+08:00"); let c = calendar()
        XCTAssertEqual(ChatTime.label(date("2026-11-14T09:05:00+08:00"), now: now, calendar: c), "09:05")
        XCTAssertEqual(ChatTime.label(date("2026-11-13T09:05:00+08:00"), now: now, calendar: c), "昨天 09:05")
        XCTAssertEqual(ChatTime.label(date("2026-11-12T09:05:00+08:00"), now: now, calendar: c), "11月12日 09:05")
        XCTAssertEqual(ChatTime.label(date("2025-11-12T09:05:00+08:00"), now: now, calendar: c), "2025年11月12日 09:05")
    }
    func testYesterdayUsesLocalDayBoundaryInsteadOfElapsed24Hours() {
        XCTAssertEqual(ChatTime.label(date("2026-11-13T23:59:00+08:00"), now: date("2026-11-14T00:01:00+08:00"), calendar: calendar()), "昨天 23:59")
        XCTAssertEqual(ChatTime.label(date("2026-03-08T00:30:00-08:00"), now: date("2026-03-09T00:15:00-07:00"), calendar: calendar("America/Los_Angeles")), "昨天 00:30")
    }
    func testInvalidServerTimestampDoesNotBecomeNowOr1970() {
        for value in [0, -1, Double.nan, .infinity] { XCTAssertNil(ChatTime.date(milliseconds: value)) }
        XCTAssertNil(ChatTime.date(milliseconds: nil))
    }
}

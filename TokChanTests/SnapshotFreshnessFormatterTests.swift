import Foundation
import XCTest
@testable import TokChan

final class SnapshotFreshnessFormatterTests: XCTestCase {
    func testNoSuccessfulSnapshotHasNoFreshnessCopy() {
        XCTAssertNil(SnapshotFreshnessFormatter.text(fetchedAt: nil, dataDate: "2026-09-06"))
    }

    func testCurrentDataDateOnlyShowsFetchFreshness() throws {
        let calendar = utcCalendar
        let now = try date("2026-09-06T12:00:00Z")
        let fetchedAt = try date("2026-09-06T11:00:00Z")

        let text = SnapshotFreshnessFormatter.text(
            fetchedAt: fetchedAt,
            dataDate: "2026-09-06",
            now: now,
            locale: Locale(identifier: "zh_CN"),
            calendar: calendar
        )

        XCTAssertNotNil(text)
        XCTAssertTrue(text?.hasPrefix("更新于 ") == true)
        XCTAssertFalse(text?.contains("数据日期") == true)
    }

    func testNonGregorianInputCalendarStillComparesGregorianServerDateInItsTimeZone() throws {
        var buddhistCalendar = Calendar(identifier: .buddhist)
        buddhistCalendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 14 * 60 * 60))

        let text = SnapshotFreshnessFormatter.text(
            fetchedAt: try date("2026-09-05T12:00:00Z"),
            dataDate: "2026-09-06",
            now: try date("2026-09-05T12:30:00Z"),
            locale: Locale(identifier: "zh_CN"),
            calendar: buddhistCalendar
        )

        XCTAssertNotNil(text)
        XCTAssertFalse(text?.contains("数据日期") == true)
    }

    func testStaleServerDateIsIncludedVerbatim() throws {
        let text = SnapshotFreshnessFormatter.text(
            fetchedAt: try date("2026-09-06T11:00:00Z"),
            dataDate: "2026-09-05",
            now: try date("2026-09-06T12:00:00Z"),
            locale: Locale(identifier: "zh_CN"),
            calendar: utcCalendar
        )

        XCTAssertTrue(text?.hasPrefix("数据日期 2026-09-05 · 更新于 ") == true)
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ value: String) throws -> Date {
        try XCTUnwrap(ISO8601DateFormatter().date(from: value))
    }
}

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
        XCTAssertTrue(text?.hasPrefix("统计读取于 ") == true)
        XCTAssertFalse(text?.contains("数据日期") == true)
    }

    func testSubMinuteAgeReadsAsJustFetchedInsteadOfZeroSecondsFromNow() throws {
        let now = try date("2026-09-06T12:00:00Z")

        for age in [0.0, 1.0, 59.0] {
            let text = SnapshotFreshnessFormatter.text(
                fetchedAt: now.addingTimeInterval(-age),
                dataDate: "2026-09-06",
                now: now,
                locale: Locale(identifier: "zh_CN"),
                calendar: utcCalendar
            )

            XCTAssertEqual(text, "统计刚刚读取", "age \(age) must not render as a future read")
        }
    }

    func testClockRollbackNeverRendersTheReadAsHappeningLater() throws {
        let now = try date("2026-09-06T12:00:00Z")

        let text = SnapshotFreshnessFormatter.text(
            fetchedAt: now.addingTimeInterval(3600),
            dataDate: "2026-09-06",
            now: now,
            locale: Locale(identifier: "zh_CN"),
            calendar: utcCalendar
        )

        XCTAssertEqual(text, "统计刚刚读取")
    }

    func testStaleServerDateStillPrefixesAJustFetchedRead() throws {
        let now = try date("2026-09-06T12:00:00Z")

        let text = SnapshotFreshnessFormatter.text(
            fetchedAt: now.addingTimeInterval(-5),
            dataDate: "2026-09-05",
            now: now,
            locale: Locale(identifier: "zh_CN"),
            calendar: utcCalendar
        )

        XCTAssertEqual(text, "数据日期 2026-09-05 · 统计刚刚读取")
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

        XCTAssertTrue(text?.hasPrefix("数据日期 2026-09-05 · 统计读取于 ") == true)
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

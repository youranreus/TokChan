import XCTest
@testable import TokChan

final class AutosubmitModelsTests: XCTestCase {
    func testDecodesCurrentCLIStatus() throws {
        let json = #"""
        {
          "enabled":true,
          "intervalMinutes":120,
          "scheduler":"launchd",
          "clients":[],
          "since":null,
          "until":null,
          "year":null,
          "today":false,
          "yesterday":false,
          "week":false,
          "month":false,
          "managedExecutable":"/tmp/tokscale",
          "managedExecutableVersion":"4.15.0",
          "managedExecutableStale":false,
          "lastRunAtMs":1788419585026,
          "lastError":null
        }
        """#

        let status = try JSONDecoder().decode(AutosubmitStatus.self, from: Data(json.utf8))
        XCTAssertTrue(status.enabled)
        XCTAssertEqual(status.intervalMinutes, 120)
        XCTAssertEqual(status.scheduler, "launchd")
        XCTAssertEqual(status.managedExecutableVersion, "4.15.0")
        XCTAssertEqual(status.filterKind, .all)
        XCTAssertEqual(status.dateFilterSummary, "全部时间")
        XCTAssertNotNil(status.lastRunAt)
    }

    func testMissingOptionalStatusFieldsGetSafeDefaults() throws {
        let status = try JSONDecoder().decode(
            AutosubmitStatus.self,
            from: Data(#"{"enabled":false}"#.utf8)
        )
        XCTAssertFalse(status.enabled)
        XCTAssertEqual(status.intervalMinutes, 1_440)
        XCTAssertEqual(status.clients, [])
        XCTAssertFalse(status.managedExecutableStale)
    }

    func testSummarizesConfiguredDateRange() throws {
        let status = try JSONDecoder().decode(
            AutosubmitStatus.self,
            from: Data(#"{"enabled":true,"since":"2026-01-01","until":"2026-09-03"}"#.utf8)
        )

        XCTAssertEqual(status.filterKind, .range)
        XCTAssertEqual(status.dateFilterSummary, "2026-01-01 – 2026-09-03")
    }
}

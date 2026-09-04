import XCTest
@testable import TokChan

final class DailyUsageTests: XCTestCase {
    func testDayUsesServerEndBucketAndDoesNotBorrowWeeklyRank() throws {
        let json = #"""
        {"period":"week","dateRange":{"start":"2026-08-29","end":"2026-09-04"},
         "user":{"username":"user","rank":4},"stats":{"totalTokens":900,"totalCost":90,"activeDays":7},
         "contributions":[
          {"date":"2026-09-03","totals":{"tokens":800,"cost":80},"clients":[]},
          {"date":"2026-09-04","totals":{"tokens":100,"cost":10},
           "tokenBreakdown":{"input":10,"output":5,"cacheRead":80,"cacheWrite":3,"reasoning":2},
           "clients":[{"client":"codex","modelId":"model","tokens":{"input":10,"output":5,"cacheRead":80,"cacheWrite":3,"reasoning":2},"cost":10}]}]}
        """#
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: Data(json.utf8))
        let day = try DashboardData.day(from: response)
        XCTAssertEqual(day.period, .day)
        XCTAssertEqual(day.totalTokens, 100)
        XCTAssertEqual(day.totalCost, 10)
        XCTAssertEqual(day.activeDays, 1)
        XCTAssertEqual(day.breakdown?.cacheRead, 80)
        XCTAssertEqual(day.clients.first?.models.first?.tokens, 100)
        XCTAssertEqual(day.clients.first?.percentage, 1)
        XCTAssertNil(day.rank)
        XCTAssertEqual(day.dateRange?.start, "2026-09-04")
        let emptyJSON = json.replacingOccurrences(of: "\"end\":\"2026-09-04\"", with: "\"end\":\"2026-09-05\"")
        let empty = try DashboardData.day(from: JSONDecoder().decode(PublicProfileResponse.self, from: Data(emptyJSON.utf8)))
        XCTAssertEqual(empty.totalTokens, 0)
        XCTAssertEqual(empty.activeDays, 0)
        XCTAssertTrue(empty.clients.isEmpty)
    }
}

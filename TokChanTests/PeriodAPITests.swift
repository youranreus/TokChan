import Foundation
import XCTest
@testable import TokChan

final class PeriodAPITests: XCTestCase {
    func testEncodesEachPeriodAndUsernameAndUsesServerBreakdown() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = LiveTokscaleAPIClient(session: session)
        for period in ProfilePeriod.allCases {
            let profile = try await api.fetchProfile(username: "name/with space", period: period)
            XCTAssertEqual(profile.period, period)
            XCTAssertEqual(profile.dateRange?.start, period == .day ? "2026-09-04" : "2026-08-29")
            XCTAssertEqual(profile.breakdown?.cacheRead, 700)
            XCTAssertEqual(profile.totalTokens, 1000)
        }
    }

    func testRejectsWrongResponsePeriod() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let api = LiveTokscaleAPIClient(session: session)
        do {
            _ = try await api.fetchProfile(username: "mismatch", period: .week)
            XCTFail("Must reject lifetime data for a week request")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("时间范围"))
        }
    }
}

private final class ProfileURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let period = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "period" })?.value)
            if !url.path.contains("mismatch") {
                XCTAssertTrue(url.absoluteString.contains("name%2Fwith%20space"))
            }
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any])
            json["period"] = url.path.contains("mismatch") ? "all" : period
            json["dateRange"] = ["start": "2026-08-29", "end": "2026-09-04"]
            var contributions = try XCTUnwrap(json["contributions"] as? [[String: Any]])
            contributions[0]["date"] = "2026-09-04"
            contributions[0]["totals"] = ["tokens": 1000, "cost": 12.5]
            contributions[0]["tokenBreakdown"] = ["input": 100, "output": 150, "cacheRead": 700, "cacheWrite": 25, "reasoning": 25]
            json["contributions"] = contributions
            json["stats"] = ["totalTokens": 1000, "totalCost": 12.5, "activeDays": 7,
                             "inputTokens": 100, "outputTokens": 150, "cacheReadTokens": 700,
                             "cacheWriteTokens": 25, "reasoningTokens": 25]
            let data = try JSONSerialization.data(withJSONObject: json)
            let response = try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

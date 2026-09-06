import Foundation
import XCTest
@testable import TokChan

final class PeriodAPITests: XCTestCase {
    override func setUp() {
        super.setUp()
        ProfileURLProtocol.reset()
    }

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

    func testBatchUsesThreeRevalidatedRequestsAndDerivesDayFromWeek() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let batch = try await LiveTokscaleAPIClient(session: session)
            .fetchDashboardBatch(username: "name/with space")

        XCTAssertEqual(Set(batch.profiles.keys), Set(ProfilePeriod.allCases))
        XCTAssertEqual(batch.profiles[.day]?.dateRange?.displayText, "2026-09-04 – 2026-09-04")
        let requests = ProfileURLProtocol.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(Set(requests.compactMap { URLComponents(url: $0.url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "period" })?.value }), Set(["all", "week", "month"]))
        XCTAssertTrue(requests.allSatisfy { $0.cachePolicy == .reloadRevalidatingCacheData })
        XCTAssertTrue(requests.allSatisfy { $0.value(forHTTPHeaderField: "Cache-Control") == "no-cache" })
        XCTAssertTrue(requests.allSatisfy { $0.timeoutInterval == 30 })
    }

    func testBatchFailsWhenAnyRemotePeriodFails() async {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ProfileURLProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        ProfileURLProtocol.fail(period: "month")

        do {
            _ = try await LiveTokscaleAPIClient(session: session)
                .fetchDashboardBatch(username: "name/with space")
            XCTFail("A partial remote batch must not be published")
        } catch {
            XCTAssertEqual((error as? URLError)?.code, .timedOut)
        }
    }
}

private final class ProfileURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var requests: [URLRequest] = []
    private static var failingPeriod: String?

    static func reset() {
        lock.lock()
        requests = []
        failingPeriod = nil
        lock.unlock()
    }

    static func fail(period: String) {
        lock.lock()
        failingPeriod = period
        lock.unlock()
    }

    static func recordedRequests() -> [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            Self.lock.lock()
            Self.requests.append(request)
            Self.lock.unlock()
            let url = try XCTUnwrap(request.url)
            let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
            let period = try XCTUnwrap(components.queryItems?.first(where: { $0.name == "period" })?.value)
            Self.lock.lock()
            let shouldFail = Self.failingPeriod == period
            Self.lock.unlock()
            if shouldFail { throw URLError(.timedOut) }
            if !url.path.contains("mismatch") {
                XCTAssertTrue(url.absoluteString.contains("name%2Fwith%20space"))
            }
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8)) as? [String: Any])
            json["period"] = url.path.contains("mismatch") ? "all" : period
            if !url.path.contains("mismatch") {
                var user = try XCTUnwrap(json["user"] as? [String: Any])
                user["username"] = "name/with space"
                json["user"] = user
            }
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

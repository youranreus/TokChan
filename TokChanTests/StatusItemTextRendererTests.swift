import XCTest
@testable import TokChan

final class StatusItemTextRendererTests: XCTestCase {
    func testReplacesEverySupportedPlaceholderAndPreservesUnknownContent() throws {
        let data = try dashboardData()
        let token = DisplayFormatters.compactNumber(data.totalTokens)

        XCTAssertEqual(
            StatusItemTextRenderer.render(
                template: "{token} / {cost} / {token} / {unknown} / {cost}",
                data: data
            ),
            "\(token) / $12.50 / \(token) / {unknown} / $12.50"
        )
    }

    func testLeavesPlainAndEmptyTemplatesUnchanged() throws {
        let data = try dashboardData()

        XCTAssertEqual(StatusItemTextRenderer.render(template: "今日用量", data: data), "今日用量")
        XCTAssertEqual(StatusItemTextRenderer.render(template: "", data: data), "")
    }

    func testUsesCompactTokensAndDollarPrefixedCostForZeroValues() throws {
        var json = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(ProfileModelsTests.profileJSON.utf8))
                as? [String: Any]
        )
        var stats = try XCTUnwrap(json["stats"] as? [String: Any])
        stats["totalTokens"] = 0
        stats["totalCost"] = 0
        json["stats"] = stats
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: JSONSerialization.data(withJSONObject: json)
        )
        let data = DashboardData(response: response)

        XCTAssertEqual(
            StatusItemTextRenderer.render(template: "{token} · {cost}", data: data),
            "\(DisplayFormatters.compactNumber(0)) · $0.00"
        )
    }

    private func dashboardData() throws -> DashboardData {
        let response = try JSONDecoder().decode(
            PublicProfileResponse.self,
            from: Data(ProfileModelsTests.profileJSON.utf8)
        )
        return DashboardData(response: response)
    }
}

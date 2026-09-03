import XCTest
@testable import TokChan

final class ProfileModelsTests: XCTestCase {
    func testDecodesAndAggregatesClientsWithModelsByTokens() throws {
        let data = Data(Self.profileJSON.utf8)
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: data)
        let dashboard = DashboardData(response: response)

        XCTAssertEqual(dashboard.username, "youranreus")
        XCTAssertEqual(dashboard.clients.map(\.id), ["codex", "claude"])
        XCTAssertEqual(dashboard.clients[0].tokens, 850)
        XCTAssertEqual(dashboard.clients[0].models.map(\.id), ["gpt-5.6-sol", "gpt-5.6-luna"])
        XCTAssertEqual(dashboard.clients[0].percentage, 0.85, accuracy: 0.0001)
        XCTAssertEqual(dashboard.clients[1].models.first?.id, "claude-opus-5")
    }

    func testMissingOptionalBreakdownFieldsDecodeAsZero() throws {
        let data = Data(Self.sparseProfileJSON.utf8)
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: data)
        let dashboard = DashboardData(response: response)

        XCTAssertEqual(dashboard.clients.first?.tokens, 0)
        XCTAssertEqual(dashboard.clients.first?.cost, 0)
        XCTAssertEqual(dashboard.clients.first?.models, [])
    }

    static let profileJSON = #"""
    {
      "user": {"username":"youranreus","displayName":"Youran","avatarUrl":null,"rank":42},
      "stats": {"totalTokens":1000,"totalCost":12.5,"activeDays":7},
      "updatedAt":"2026-09-03T01:02:03.000Z",
      "contributions":[
        {"clients":[
          {"client":"codex","models":{
            "gpt-5.6-sol":{"tokens":600,"cost":6},
            "gpt-5.6-luna":{"tokens":250,"cost":2.5}
          },"tokens":{"input":50,"output":50,"cacheRead":700,"cacheWrite":25,"reasoning":25},"cost":8.5},
          {"client":"claude","modelId":"claude-opus-5","tokens":{"input":50,"output":100},"cost":4}
        ]}
      ]
    }
    """#

    static let sparseProfileJSON = #"""
    {
      "user":{"username":"empty","displayName":null,"avatarUrl":null,"rank":null},
      "stats":{"totalTokens":0,"totalCost":0,"activeDays":0},
      "updatedAt":null,
      "contributions":[{"clients":[{"client":"codex"}]}]
    }
    """#
}

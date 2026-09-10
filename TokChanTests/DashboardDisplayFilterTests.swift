import XCTest
@testable import TokChan

final class DashboardDisplayFilterTests: XCTestCase {
    private let clients = [
        ClientUsageGroup(
            id: "cursor",
            tokens: 100,
            cost: 9,
            percentage: 0.6,
            models: [
                ModelUsage(id: "zero", tokens: 50, cost: 0),
                ModelUsage(id: "positive", tokens: 30, cost: 2),
                ModelUsage(id: "negative", tokens: 20, cost: -0.5)
            ]
        ),
        ClientUsageGroup(
            id: "codex",
            tokens: 80,
            cost: 0,
            percentage: 0.4,
            models: [ModelUsage(id: "also-zero", tokens: 80, cost: -0.0)]
        )
    ]

    func testDefaultPreferencesReturnTheCompleteOrderedList() {
        XCTAssertEqual(
            DashboardDisplayFilter.clients(from: clients, preferences: preferences()),
            clients
        )
    }

    func testZeroCostFilterRemovesOnlyExactlyZeroModelsAndPreservesClientSummary() {
        let result = DashboardDisplayFilter.clients(
            from: clients,
            preferences: preferences(hideZeroCostModels: true)
        )

        XCTAssertEqual(result.map(\.id), ["cursor", "codex"])
        XCTAssertEqual(result[0].models.map(\.id), ["positive", "negative"])
        XCTAssertEqual(result[0].tokens, clients[0].tokens)
        XCTAssertEqual(result[0].cost, clients[0].cost)
        XCTAssertEqual(result[0].percentage, clients[0].percentage)
        XCTAssertTrue(result[1].models.isEmpty)
        XCTAssertEqual(result[1].cost, 0)
    }

    func testSelectedClientsRemainVisibleWhileMasterSwitchIsOff() {
        let result = DashboardDisplayFilter.clients(
            from: clients,
            preferences: preferences(hiddenClientIDs: ["cursor"])
        )

        XCTAssertEqual(result, clients)
    }

    func testEnabledClientFilterPreservesUnselectedClientOrderAndModels() {
        let result = DashboardDisplayFilter.clients(
            from: clients,
            preferences: preferences(hiddenClientsEnabled: true, hiddenClientIDs: ["cursor"])
        )

        XCTAssertEqual(result, [clients[1]])
    }

    func testEnabledClientFilterCanProduceAnEmptyProjectionFromNonemptySource() {
        let result = DashboardDisplayFilter.clients(
            from: clients,
            preferences: preferences(
                hiddenClientsEnabled: true,
                hiddenClientIDs: Set(clients.map(\.id))
            )
        )

        XCTAssertTrue(result.isEmpty)
        XCTAssertFalse(clients.isEmpty)
    }

    func testClientAndModelFiltersComposeWithoutMutatingTheSource() {
        let source = clients
        let result = DashboardDisplayFilter.clients(
            from: source,
            preferences: preferences(
                hideZeroCostModels: true,
                hiddenClientsEnabled: true,
                hiddenClientIDs: ["codex"]
            )
        )

        XCTAssertEqual(result.map(\.id), ["cursor"])
        XCTAssertEqual(result[0].models.map(\.id), ["positive", "negative"])
        XCTAssertEqual(clients, source)
        XCTAssertEqual(source[0].models.map(\.id), ["zero", "positive", "negative"])
    }

    private func preferences(
        hideZeroCostModels: Bool = false,
        hiddenClientsEnabled: Bool = false,
        hiddenClientIDs: Set<String> = []
    ) -> UserPreferences {
        UserPreferences(
            username: "youranreus",
            tokscaleVersion: "latest",
            npxPath: "",
            hideZeroCostModels: hideZeroCostModels,
            hiddenClientsEnabled: hiddenClientsEnabled,
            hiddenClientIDs: hiddenClientIDs
        )
    }
}

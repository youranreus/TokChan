import XCTest
@testable import TokChan

final class AutosubmitSettingsDraftTests: XCTestCase {
    func testLateStatusInitializesPristineDraft() throws {
        var draft = AutosubmitSettingsDraft(status: nil)
        let status = try makeStatus(enabled: true, interval: 120, clients: ["codex"], week: true)

        draft.synchronize(with: status)

        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.configuration, AutosubmitConfiguration(
            enabled: true,
            intervalMinutes: 120,
            clients: ["codex"],
            filterKind: .week,
            year: "",
            since: "",
            until: ""
        ))
    }

    func testLateStatusDoesNotOverwriteDirtyDraft() throws {
        var draft = AutosubmitSettingsDraft(status: nil)
        draft.edit(\AutosubmitSettingsDraft.enabled, to: true)
        draft.edit(\AutosubmitSettingsDraft.intervalMinutes, to: 30)

        draft.synchronize(with: try makeStatus(enabled: false, interval: 240))

        XCTAssertTrue(draft.isDirty)
        XCTAssertTrue(draft.enabled)
        XCTAssertEqual(draft.intervalMinutes, 30)
    }

    func testSuccessfulApplyConfirmationReplacesDraftAndClearsDirtyState() throws {
        var draft = AutosubmitSettingsDraft(status: nil)
        draft.edit(\AutosubmitSettingsDraft.clientsText, to: "codex, pi")
        XCTAssertTrue(draft.isDirty)

        let confirmed = try makeStatus(enabled: true, interval: 60, clients: ["codex", "pi"])
        draft.confirm(with: confirmed)

        XCTAssertFalse(draft.isDirty)
        XCTAssertEqual(draft.clientsText, "codex, pi")
        XCTAssertEqual(draft.configuration.enabled, true)
        XCTAssertEqual(draft.configuration.intervalMinutes, 60)
    }

    private func makeStatus(
        enabled: Bool,
        interval: Int,
        clients: [String] = [],
        week: Bool = false
    ) throws -> AutosubmitStatus {
        let clientsData = try JSONSerialization.data(withJSONObject: clients)
        let clientsJSON = try XCTUnwrap(String(data: clientsData, encoding: .utf8))
        let json = """
        {
          "enabled": \(enabled),
          "intervalMinutes": \(interval),
          "clients": \(clientsJSON),
          "week": \(week)
        }
        """
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(json.utf8))
    }
}

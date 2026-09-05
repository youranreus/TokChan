import Foundation
import ServiceManagement
import XCTest
@testable import TokChan

@MainActor
final class LaunchAtLoginSettingsModelTests: XCTestCase {
    func testSystemStatusMappings() {
        let cases: [(SMAppService.Status, LaunchAtLoginStatus)] = [
            (.enabled, .enabled),
            (.notRegistered, .notRegistered),
            (.requiresApproval, .requiresApproval),
            (.notFound, .notFound)
        ]

        for (systemStatus, expectedStatus) in cases {
            XCTAssertEqual(
                LaunchAtLoginStatus(systemStatus: systemStatus),
                expectedStatus
            )
        }
    }

    func testStatusMappings() {
        let cases: [(LaunchAtLoginStatus, Bool, Bool)] = [
            (.enabled, true, true),
            (.notRegistered, false, true),
            (.requiresApproval, true, true),
            (.notFound, false, false)
        ]

        for (status, isEnabled, isAvailable) in cases {
            let model = LaunchAtLoginSettingsModel(
                service: FakeLaunchAtLoginService(status: status)
            )

            XCTAssertEqual(model.status, status)
            XCTAssertEqual(model.isEnabled, isEnabled)
            XCTAssertEqual(model.isAvailable, isAvailable)
        }
    }

    func testRefreshReadsExternallyChangedStatusAndClearsStaleError() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = testError("第一次失败")
        let model = LaunchAtLoginSettingsModel(service: service)
        model.setEnabled(true)
        service.status = .enabled

        model.refresh()

        XCTAssertEqual(model.status, .enabled)
        XCTAssertTrue(model.isEnabled)
        XCTAssertNil(model.errorMessage)
    }

    func testEnablingRegistersImmediatelyAndReconcilesPendingApproval() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLoginSettingsModel(service: service)

        model.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(service.unregisterCallCount, 0)
        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertTrue(model.isEnabled)
        XCTAssertNil(model.errorMessage)
        XCTAssertFalse(model.isUpdating)
    }

    func testThrownRegisterReconcilesPendingApprovalWithoutContradictoryError() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        service.registerError = testError("需要用户批准")
        let model = LaunchAtLoginSettingsModel(service: service)

        model.setEnabled(true)

        XCTAssertEqual(model.status, .requiresApproval)
        XCTAssertTrue(model.isEnabled)
        XCTAssertNil(model.errorMessage)
    }

    func testDisablingUnregistersImmediatelyAndReconcilesStatus() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        service.statusAfterUnregister = .notRegistered
        let model = LaunchAtLoginSettingsModel(service: service)

        model.setEnabled(false)

        XCTAssertEqual(service.registerCallCount, 0)
        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(model.status, .notRegistered)
        XCTAssertFalse(model.isEnabled)
        XCTAssertNil(model.errorMessage)
    }

    func testRegisterFailureRestoresSystemStatusAndShowsError() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.statusAfterRegister = .notRegistered
        service.registerError = testError("注册被拒绝")
        let model = LaunchAtLoginSettingsModel(service: service)

        model.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 1)
        XCTAssertEqual(model.status, .notRegistered)
        XCTAssertFalse(model.isEnabled)
        XCTAssertEqual(model.errorMessage, "无法启用登录时启动：注册被拒绝")
        XCTAssertFalse(model.isUpdating)
    }

    func testUnregisterFailureRestoresSystemStatusAndShowsError() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        service.statusAfterUnregister = .enabled
        service.unregisterError = testError("无法移除登录项")
        let model = LaunchAtLoginSettingsModel(service: service)

        model.setEnabled(false)

        XCTAssertEqual(service.unregisterCallCount, 1)
        XCTAssertEqual(model.status, .enabled)
        XCTAssertTrue(model.isEnabled)
        XCTAssertEqual(model.errorMessage, "无法关闭登录时启动：无法移除登录项")
        XCTAssertFalse(model.isUpdating)
    }

    func testNewAttemptClearsPreviousError() {
        let service = FakeLaunchAtLoginService(status: .notRegistered)
        service.registerError = testError("第一次失败")
        let model = LaunchAtLoginSettingsModel(service: service)
        model.setEnabled(true)
        service.registerError = nil
        service.statusAfterRegister = .enabled

        model.setEnabled(true)

        XCTAssertEqual(service.registerCallCount, 2)
        XCTAssertEqual(model.status, .enabled)
        XCTAssertNil(model.errorMessage)
    }

    func testPendingApprovalCanOpenLoginItemsSettings() {
        let service = FakeLaunchAtLoginService(status: .requiresApproval)
        let model = LaunchAtLoginSettingsModel(service: service)

        model.openSystemSettingsLoginItems()

        XCTAssertEqual(service.openSettingsCallCount, 1)
    }

    func testOpenSettingsIsIgnoredWhenApprovalIsNotRequired() {
        let service = FakeLaunchAtLoginService(status: .enabled)
        let model = LaunchAtLoginSettingsModel(service: service)

        model.openSystemSettingsLoginItems()

        XCTAssertEqual(service.openSettingsCallCount, 0)
    }

    func testUITestingFactoryUsesInMemoryService() throws {
        let service = LaunchAtLoginServiceFactory.make(arguments: ["--ui-testing"])

        XCTAssertTrue(service is UITestingLaunchAtLoginService)
        XCTAssertEqual(service.status, .notRegistered)

        try service.register()
        XCTAssertEqual(service.status, .enabled)

        try service.unregister()
        XCTAssertEqual(service.status, .notRegistered)
    }

    private func testError(_ message: String) -> NSError {
        NSError(
            domain: "LaunchAtLoginSettingsModelTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}

private final class FakeLaunchAtLoginService: LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus
    var statusAfterRegister: LaunchAtLoginStatus?
    var statusAfterUnregister: LaunchAtLoginStatus?
    var registerError: Error?
    var unregisterError: Error?
    private(set) var registerCallCount = 0
    private(set) var unregisterCallCount = 0
    private(set) var openSettingsCallCount = 0

    init(status: LaunchAtLoginStatus) {
        self.status = status
    }

    func register() throws {
        registerCallCount += 1
        if let statusAfterRegister {
            status = statusAfterRegister
        }
        if let registerError {
            throw registerError
        }
    }

    func unregister() throws {
        unregisterCallCount += 1
        if let statusAfterUnregister {
            status = statusAfterUnregister
        }
        if let unregisterError {
            throw unregisterError
        }
    }

    func openSystemSettingsLoginItems() {
        openSettingsCallCount += 1
    }
}

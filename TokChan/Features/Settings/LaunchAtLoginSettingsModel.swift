import Foundation

@MainActor
final class LaunchAtLoginSettingsModel: ObservableObject {
    @Published private(set) var status: LaunchAtLoginStatus
    @Published private(set) var isUpdating = false
    @Published private(set) var errorMessage: String?

    private let service: LaunchAtLoginServicing

    init(service: LaunchAtLoginServicing) {
        self.service = service
        status = service.status
    }

    var isEnabled: Bool {
        status == .enabled || status == .requiresApproval
    }

    func refresh() {
        status = service.status
        errorMessage = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }

        isUpdating = true
        errorMessage = nil

        var operationError: Error?
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
        } catch {
            operationError = error
        }

        status = service.status
        if let operationError, !statusMatchesRequest(enabled) {
            let action = enabled ? "启用" : "关闭"
            errorMessage = "无法\(action)登录时启动：\(operationError.localizedDescription)"
        }
        isUpdating = false
    }

    private func statusMatchesRequest(_ enabled: Bool) -> Bool {
        if enabled {
            return status == .enabled || status == .requiresApproval
        }
        return status == .notRegistered
    }

    func openSystemSettingsLoginItems() {
        guard status == .requiresApproval else { return }
        service.openSystemSettingsLoginItems()
    }
}

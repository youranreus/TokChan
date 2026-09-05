import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case enabled
    case notRegistered
    case requiresApproval
    case notFound

    init(systemStatus: SMAppService.Status) {
        switch systemStatus {
        case .enabled:
            self = .enabled
        case .notRegistered:
            self = .notRegistered
        case .requiresApproval:
            self = .requiresApproval
        case .notFound:
            self = .notFound
        @unknown default:
            self = .notFound
        }
    }
}

@MainActor
protocol LaunchAtLoginServicing {
    var status: LaunchAtLoginStatus { get }

    func register() throws
    func unregister() throws
    func openSystemSettingsLoginItems()
}

struct SystemLaunchAtLoginService: LaunchAtLoginServicing {
    private let service: SMAppService

    init(service: SMAppService = .mainApp) {
        self.service = service
    }

    var status: LaunchAtLoginStatus {
        LaunchAtLoginStatus(systemStatus: service.status)
    }

    func register() throws {
        try service.register()
    }

    func unregister() throws {
        try service.unregister()
    }

    func openSystemSettingsLoginItems() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

@MainActor
enum LaunchAtLoginServiceFactory {
    static func make(arguments: [String] = CommandLine.arguments) -> LaunchAtLoginServicing {
        #if DEBUG
        if arguments.contains("--ui-testing") {
            return UITestingLaunchAtLoginService()
        }
        #endif
        return SystemLaunchAtLoginService()
    }
}

#if DEBUG
final class UITestingLaunchAtLoginService: LaunchAtLoginServicing {
    private(set) var status: LaunchAtLoginStatus = .notRegistered

    func register() throws {
        status = .enabled
    }

    func unregister() throws {
        status = .notRegistered
    }

    func openSystemSettingsLoginItems() {}
}
#endif

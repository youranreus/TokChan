import Combine
import Foundation
import Sparkle

@MainActor
protocol AppUpdating: AnyObject {
    var canCheckForUpdates: Bool { get }
    func checkForUpdates()
}

@MainActor
final class AppUpdater: ObservableObject, AppUpdating {
    @Published private(set) var canCheckForUpdates: Bool

    private let checkAction: () -> Void
    private var availabilityObservation: AnyCancellable?

    init(
        canCheckForUpdates: Bool,
        checkAction: @escaping () -> Void,
        availability: AnyPublisher<Bool, Never>? = nil
    ) {
        self.canCheckForUpdates = canCheckForUpdates
        self.checkAction = checkAction
        availabilityObservation = availability?
            .removeDuplicates()
            .sink { [weak self] in self?.canCheckForUpdates = $0 }
    }

    func checkForUpdates() {
        guard canCheckForUpdates else { return }
        canCheckForUpdates = false
        checkAction()
    }

    static func live() -> AppUpdater {
        let controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        return AppUpdater(
            canCheckForUpdates: controller.updater.canCheckForUpdates,
            checkAction: { [controller] in controller.checkForUpdates(nil) },
            availability: controller.updater.publisher(for: \.canCheckForUpdates).eraseToAnyPublisher()
        )
    }

    static func offlineTest(isBusy: Bool = false) -> AppUpdater {
        AppUpdater(canCheckForUpdates: !isBusy, checkAction: {})
    }
}

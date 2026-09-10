import AppKit
import SwiftUI

@MainActor
final class TokChanApplicationDelegate: NSObject, NSApplicationDelegate {
    let viewModel: DashboardViewModel
    let launchAtLoginModel: LaunchAtLoginSettingsModel
    let customPricingViewModel: CustomPricingViewModel
    let appUpdater: AppUpdater
    private var statusItemCoordinator: NSStatusItemCoordinator?
    private var wakeObserver: SystemWakeObserver?

    override init() {
        let api: TokscaleAPIService
        let cli: TokscaleCLIService
        let localDataSource: DashboardDataReading
        let preferences: PreferencesStoring
        let npxLocator: NpxLocating
        let cacheStore: DashboardCacheStoring
        let customPricingCLI: CustomPricingCLIService
        let customPricingStore: CustomPricingFileStoring

        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing") {
            api = PreviewAPIService()
            let previewCLI = PreviewCLIService()
            cli = previewCLI
            localDataSource = PreviewLocalDashboardDataSource()
            customPricingCLI = previewCLI
            preferences = PreviewPreferencesStore()
            npxLocator = PreviewNpxLocator()
            cacheStore = PreviewCacheStore()
            customPricingStore = PreviewCustomPricingStore()
        } else {
            api = LiveTokscaleAPIClient()
            let runner = FoundationProcessRunner()
            let liveCLI = TokscaleCLIClient(runner: runner)
            cli = liveCLI
            localDataSource = TokscaleLocalDashboardDataSource(runner: runner)
            customPricingCLI = liveCLI
            preferences = UserDefaultsPreferencesStore()
            npxLocator = NpxLocator()
            cacheStore = FileDashboardCacheStore()
            customPricingStore = CustomPricingFileStore()
        }
        #else
        api = LiveTokscaleAPIClient()
        let runner = FoundationProcessRunner()
        let liveCLI = TokscaleCLIClient(runner: runner)
        cli = liveCLI
        localDataSource = TokscaleLocalDashboardDataSource(runner: runner)
        customPricingCLI = liveCLI
        preferences = UserDefaultsPreferencesStore()
        npxLocator = NpxLocator()
        cacheStore = FileDashboardCacheStore()
        customPricingStore = CustomPricingFileStore()
        #endif

        viewModel = DashboardViewModel(
            api: api,
            cli: cli,
            localDataSource: localDataSource,
            preferencesStore: preferences,
            npxLocator: npxLocator,
            cacheStore: cacheStore
        )
        launchAtLoginModel = LaunchAtLoginSettingsModel(
            service: LaunchAtLoginServiceFactory.make()
        )
        customPricingViewModel = CustomPricingViewModel(
            cli: customPricingCLI,
            store: customPricingStore,
            preferencesStore: preferences,
            npxLocator: npxLocator
        )
        #if DEBUG
        appUpdater = CommandLine.arguments.contains("--ui-testing")
            ? .offlineTest(isBusy: CommandLine.arguments.contains("--updater-busy"))
            : .live()
        #else
        appUpdater = .live()
        #endif
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard statusItemCoordinator == nil else { return }
        // Subscribe the status item before the first background publication can happen.
        statusItemCoordinator = NSStatusItemCoordinator(
            viewModel: viewModel,
            settingsAction: .live,
            appUpdater: appUpdater,
            terminate: { NSApplication.shared.terminate(nil) }
        )
        let observer = SystemWakeObserver { [weak self] in
            Task { @MainActor [weak self] in
                await self?.viewModel.reevaluateStatisticsAfterWake()
            }
        }
        observer.start()
        wakeObserver = observer
        viewModel.startBackgroundSynchronization()
    }

    func applicationWillTerminate(_ notification: Notification) {
        wakeObserver?.stop()
        wakeObserver = nil
        viewModel.stopBackgroundSynchronization()
    }
}

@main
struct TokChanApp: App {
    @NSApplicationDelegateAdaptor(TokChanApplicationDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView(
                viewModel: appDelegate.viewModel,
                launchAtLoginModel: appDelegate.launchAtLoginModel,
                customPricingViewModel: appDelegate.customPricingViewModel,
                appUpdater: appDelegate.appUpdater
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}

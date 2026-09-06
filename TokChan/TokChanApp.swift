import AppKit
import SwiftUI

@MainActor
final class TokChanApplicationDelegate: NSObject, NSApplicationDelegate {
    let viewModel: DashboardViewModel
    let launchAtLoginModel: LaunchAtLoginSettingsModel
    let customPricingViewModel: CustomPricingViewModel
    private var statusItemCoordinator: NSStatusItemCoordinator?

    override init() {
        let api: TokscaleAPIService
        let cli: TokscaleCLIService
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
            customPricingCLI = previewCLI
            preferences = PreviewPreferencesStore()
            npxLocator = PreviewNpxLocator()
            cacheStore = PreviewCacheStore()
            customPricingStore = PreviewCustomPricingStore()
        } else {
            api = LiveTokscaleAPIClient()
            let liveCLI = TokscaleCLIClient(runner: FoundationProcessRunner())
            cli = liveCLI
            customPricingCLI = liveCLI
            preferences = UserDefaultsPreferencesStore()
            npxLocator = NpxLocator()
            cacheStore = FileDashboardCacheStore()
            customPricingStore = CustomPricingFileStore()
        }
        #else
        api = LiveTokscaleAPIClient()
        let liveCLI = TokscaleCLIClient(runner: FoundationProcessRunner())
        cli = liveCLI
        customPricingCLI = liveCLI
        preferences = UserDefaultsPreferencesStore()
        npxLocator = NpxLocator()
        cacheStore = FileDashboardCacheStore()
        customPricingStore = CustomPricingFileStore()
        #endif

        viewModel = DashboardViewModel(
            api: api,
            cli: cli,
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
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard statusItemCoordinator == nil else { return }
        statusItemCoordinator = NSStatusItemCoordinator(
            viewModel: viewModel,
            settingsAction: .live,
            terminate: { NSApplication.shared.terminate(nil) }
        )
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
                customPricingViewModel: appDelegate.customPricingViewModel
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}

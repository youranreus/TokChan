import SwiftUI

@main
struct TokChanApp: App {
    @StateObject private var viewModel: DashboardViewModel
    @StateObject private var launchAtLoginModel: LaunchAtLoginSettingsModel
    @StateObject private var customPricingViewModel: CustomPricingViewModel

    init() {
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

        _viewModel = StateObject(
            wrappedValue: DashboardViewModel(
                api: api,
                cli: cli,
                preferencesStore: preferences,
                npxLocator: npxLocator,
                cacheStore: cacheStore
            )
        )
        let launchAtLoginService = LaunchAtLoginServiceFactory.make()
        _launchAtLoginModel = StateObject(
            wrappedValue: LaunchAtLoginSettingsModel(service: launchAtLoginService)
        )
        _customPricingViewModel = StateObject(
            wrappedValue: CustomPricingViewModel(
                cli: customPricingCLI,
                store: customPricingStore,
                preferencesStore: preferences,
                npxLocator: npxLocator
            )
        )
    }

    var body: some Scene {
        MenuBarExtra("TokChan", image: "MenuBarIcon") {
            DashboardView(viewModel: viewModel)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(
                viewModel: viewModel,
                launchAtLoginModel: launchAtLoginModel,
                customPricingViewModel: customPricingViewModel
            )
            .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}

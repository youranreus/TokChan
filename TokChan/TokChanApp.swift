import SwiftUI

@main
struct TokChanApp: App {
    @StateObject private var viewModel: DashboardViewModel

    init() {
        let api: TokscaleAPIService
        let cli: TokscaleCLIService
        let preferences: PreferencesStoring
        let npxLocator: NpxLocating
        let cacheStore: DashboardCacheStoring

        #if DEBUG
        if CommandLine.arguments.contains("--ui-testing") {
            api = PreviewAPIService()
            cli = PreviewCLIService()
            preferences = PreviewPreferencesStore()
            npxLocator = PreviewNpxLocator()
            cacheStore = PreviewCacheStore()
        } else {
            api = LiveTokscaleAPIClient()
            cli = TokscaleCLIClient(runner: FoundationProcessRunner())
            preferences = UserDefaultsPreferencesStore()
            npxLocator = NpxLocator()
            cacheStore = FileDashboardCacheStore()
        }
        #else
        api = LiveTokscaleAPIClient()
        cli = TokscaleCLIClient(runner: FoundationProcessRunner())
        preferences = UserDefaultsPreferencesStore()
        npxLocator = NpxLocator()
        cacheStore = FileDashboardCacheStore()
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
    }

    var body: some Scene {
        MenuBarExtra("TokChan", image: "MenuBarIcon") {
            DashboardView(viewModel: viewModel)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(viewModel: viewModel)
                .environment(\.locale, Locale(identifier: "zh_CN"))
        }
    }
}

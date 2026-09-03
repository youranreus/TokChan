#if DEBUG
import Foundation
import SwiftUI

struct PreviewAPIService: TokscaleAPIService {
    func fetchProfile(username: String) async throws -> DashboardData {
        let json = #"""
        {
          "user":{"username":"youranreus","displayName":"季悠然","avatarUrl":null,"rank":946},
          "stats":{"totalTokens":8963807446,"totalCost":7666.02,"activeDays":234},
          "updatedAt":"2026-09-03T07:26:40.951Z",
          "contributions":[{"clients":[
            {"client":"codex","models":{
              "gpt-5.6-sol":{"tokens":1600000000,"cost":1079.80},
              "codex-auto-review":{"tokens":32000000,"cost":3.02}
            },"tokens":{"input":180000000,"output":42000000,"cacheRead":1410000000},"cost":1082.82},
            {"client":"cursor","models":{
              "claude-opus-5-thinking-high":{"tokens":347000000,"cost":377.36},
              "composer-2.5":{"tokens":318000000,"cost":132.96}
            },"tokens":{"input":90000000,"output":25000000,"cacheRead":550000000},"cost":510.32}
          ]}]
        }
        """#
        let response = try JSONDecoder().decode(PublicProfileResponse.self, from: Data(json.utf8))
        return DashboardData(response: response)
    }
}

struct PreviewCLIService: TokscaleCLIService {
    func whoAmI(context: TokscaleCommandContext) async throws -> String { "youranreus" }
    func submit(context: TokscaleCommandContext) async throws {}

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        let json = #"""
        {
          "enabled":true,"intervalMinutes":120,"scheduler":"launchd","clients":[],
          "managedExecutableVersion":"4.15.0","managedExecutableStale":false,
          "lastRunAtMs":1788419585026,"lastError":null
        }
        """#
        return try JSONDecoder().decode(AutosubmitStatus.self, from: Data(json.utf8))
    }

    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws {}
    func disableAutosubmit(context: TokscaleCommandContext) async throws {}
    func runAutosubmitNow(context: TokscaleCommandContext) async throws {}
}

final class PreviewPreferencesStore: PreferencesStoring {
    private var value = UserPreferences(
        username: "youranreus",
        tokscaleVersion: "4.15.0",
        npxPath: "/opt/homebrew/bin/npx"
    )

    func load() -> UserPreferences { value }
    func save(_ preferences: UserPreferences) { value = preferences }
}

struct PreviewNpxLocator: NpxLocating {
    func locate(preferredPath: String?) -> URL? {
        URL(fileURLWithPath: "/opt/homebrew/bin/npx")
    }
}

struct DashboardView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        DashboardView(
            viewModel: DashboardViewModel(
                api: PreviewAPIService(),
                cli: PreviewCLIService(),
                preferencesStore: PreviewPreferencesStore(),
                npxLocator: PreviewNpxLocator(),
                cacheStore: PreviewCacheStore()
            )
        )
    }
}

final class PreviewCacheStore: DashboardCacheStoring {
    func load() -> DashboardCacheSnapshot? { nil }
    func save(_ snapshot: DashboardCacheSnapshot) throws {}
}
#endif

#if DEBUG
import Foundation
import SwiftUI

struct PreviewAPIService: TokscaleAPIService {
    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        var profiles: [ProfilePeriod: DashboardData] = [:]
        for period in ProfilePeriod.allCases {
            profiles[period] = try makeProfile(username: username, period: period)
        }
        return try DashboardProfileBatch(username: username, profiles: profiles)
    }

    private func makeProfile(username: String, period: ProfilePeriod) throws -> DashboardData {
        let scale: Double = period == .all ? 100 : (period == .month ? 10 : (period == .week ? 1 : 0.2))
        let clientIDs = ["codex", "cursor", "hermes", "pi", "unknown-agent"]
        let clients: [[String: Any]] = clientIDs.enumerated().map { index, client in
            let amount = 1000 * scale / Double(index + 1)
            let models = Dictionary(uniqueKeysWithValues: (1...8).map { number in
                ("model-\(number)", ["tokens": amount * Double(9 - number) / 36, "cost": Double(9 - number) * scale / 36])
            })
            return ["client": client, "models": models,
                    "tokens": ["input": amount * 0.1, "output": amount * 0.05,
                               "cacheRead": amount * 0.8, "cacheWrite": amount * 0.03,
                               "reasoning": amount * 0.02], "cost": scale]
        }
        let total = (1...5).reduce(0.0) { $0 + 1000 * scale / Double($1) }
        let json: [String: Any] = [
            "period": period.rawValue,
            "dateRange": ["start": period == .week ? "2026-08-29" : "2026-08-06", "end": "2026-09-04"],
            "user": ["username": username, "displayName": "季悠然", "rank": period == .day ? NSNull() : (period == .all ? 42 : 12) as Any],
            "stats": ["totalTokens": total, "totalCost": scale * 5, "activeDays": period == .week ? 7 : 30,
                      "inputTokens": total * 0.1, "outputTokens": total * 0.05,
                      "cacheReadTokens": total * 0.8, "cacheWriteTokens": total * 0.03,
                      "reasoningTokens": total * 0.02],
            "updatedAt": "2026-09-04T01:00:00Z", "contributions": [["clients": clients]]
        ]
        let data = try JSONSerialization.data(withJSONObject: json)
        return DashboardData(response: try JSONDecoder().decode(PublicProfileResponse.self, from: data))
    }
}

struct PreviewCLIService: TokscaleCLIService, CustomPricingCLIService {
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

    func customPricingFileURL(context: TokscaleCommandContext) async throws -> URL {
        URL(fileURLWithPath: "/tmp/tokchan-ui-test/custom-pricing.json")
    }

    func checkCustomPricing(context: TokscaleCommandContext) async throws -> PricingDiagnosticReport {
        PricingDiagnosticReport(
            outcome: .missingPricing,
            items: [MissingPricingItem(
                providerModel: "anthropic/claude-preview",
                provider: "anthropic",
                modelID: "claude-preview",
                messageCount: 3,
                tokenCount: 12_345,
                reason: "Tokscale 报告该模型缺少价格。"
            )],
            warnings: [],
            details: "Dry run fixture: anthropic/claude-preview is unpriced.",
            checkedAt: Date(timeIntervalSince1970: 1_788_425_600)
        )
    }
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

final class PreviewCustomPricingStore: CustomPricingFileStoring {
    private var value = CustomPricingSnapshot(
        fileURL: URL(fileURLWithPath: "/tmp/tokchan-ui-test/custom-pricing.json"),
        originalData: Data("fixture".utf8),
        entries: [
            CustomPricingEntry(
                modelID: "claude-sonnet-4-5-with-a-long-model-identifier", inputPrice: 3, outputPrice: 15,
                cacheReadPrice: 0.3, cacheWritePrice: nil,
                source: "fixture", notes: "UI testing", issue: nil
            ),
            CustomPricingEntry(
                modelID: "free-model", inputPrice: 0, outputPrice: 0,
                cacheReadPrice: nil, cacheWritePrice: nil,
                source: nil, notes: nil, issue: nil
            )
        ] + (1...14).map {
            CustomPricingEntry(modelID: "fixture-model-\($0)", inputPrice: Double($0),
                               outputPrice: Double($0 * 2), cacheReadPrice: nil,
                               cacheWritePrice: nil, source: "fixture", notes: nil, issue: nil)
        }
    )

    func load(from url: URL) throws -> CustomPricingSnapshot { value }
    func hasChanged(_ snapshot: CustomPricingSnapshot) throws -> Bool { false }

    func add(_ draft: ValidatedCustomPricingDraft, to snapshot: CustomPricingSnapshot) throws -> CustomPricingSnapshot {
        value = replacing(entries: snapshot.entries + [entry(draft)])
        return value
    }

    func update(originalModelID: String, with draft: ValidatedCustomPricingDraft,
                in snapshot: CustomPricingSnapshot) throws -> CustomPricingSnapshot {
        value = replacing(entries: snapshot.entries.filter { $0.modelID != originalModelID } + [entry(draft)])
        return value
    }

    func delete(modelID: String, from snapshot: CustomPricingSnapshot) throws -> CustomPricingSnapshot {
        value = replacing(entries: snapshot.entries.filter { $0.modelID != modelID })
        return value
    }

    private func replacing(entries: [CustomPricingEntry]) -> CustomPricingSnapshot {
        CustomPricingSnapshot(fileURL: value.fileURL, originalData: UUID().uuidString.data(using: .utf8),
                              entries: entries.sorted { $0.modelID < $1.modelID })
    }

    private func entry(_ draft: ValidatedCustomPricingDraft) -> CustomPricingEntry {
        CustomPricingEntry(modelID: draft.modelID, inputPrice: draft.inputPrice,
                           outputPrice: draft.outputPrice, cacheReadPrice: draft.cacheReadPrice,
                           cacheWritePrice: draft.cacheWritePrice, source: draft.source,
                           notes: draft.notes, issue: nil)
    }
}
#endif

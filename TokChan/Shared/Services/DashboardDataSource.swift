import Foundation

struct DashboardSourceBatch: Equatable {
    let source: DashboardDataMode
    let account: String?
    let profiles: [ProfilePeriod: DashboardData]
    let warnings: [String]

    init(
        source: DashboardDataMode,
        account: String?,
        profiles: [ProfilePeriod: DashboardData],
        warnings: [String] = []
    ) throws {
        guard Set(profiles.keys) == Set(ProfilePeriod.allCases),
              ProfilePeriod.allCases.allSatisfy({ profiles[$0]?.period == $0 }) else {
            throw DashboardSourceError.invalidGraph
        }
        self.source = source
        self.account = account
        self.profiles = profiles
        self.warnings = warnings
    }
}

enum DashboardSourceError: LocalizedError {
    case invalidGraph
    case invalidTimezone
    case incompatibleCLI(version: String, detail: String)

    var errorDescription: String? {
        switch self {
        case .invalidGraph:
            return "Tokscale 返回了无法识别的本地统计数据。"
        case .invalidTimezone:
            return "无法读取 Tokscale 统计时区，请检查 Tokscale 的 timezone 配置。"
        case let .incompatibleCLI(version, detail):
            return "Tokscale \(version) 不支持本地统计读取，请在设置中调整版本。\(detail.isEmpty ? "" : "\n\(detail)")"
        }
    }
}

enum DashboardSourceRequest {
    case local(context: TokscaleCommandContext, now: Date)
    case online(username: String)
}

protocol DashboardDataReading {
    var source: DashboardDataMode { get }
    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch
}

struct OnlineDashboardDataSource: DashboardDataReading {
    let source = DashboardDataMode.online
    let api: TokscaleAPIService

    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch {
        guard case let .online(username) = request else { throw DashboardSourceError.invalidGraph }
        let batch = try await api.fetchDashboardBatch(username: username)
        return try DashboardSourceBatch(source: .online, account: batch.username, profiles: batch.profiles)
    }
}

struct UnavailableLocalDashboardDataSource: DashboardDataReading {
    let source = DashboardDataMode.local

    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch {
        guard case let .local(context, _) = request else { throw DashboardSourceError.invalidGraph }
        throw DashboardSourceError.incompatibleCLI(version: context.version, detail: "")
    }
}

final class TokscaleLocalDashboardDataSource: DashboardDataReading {
    let source = DashboardDataMode.local
    private struct GraphExport: Decodable {
        let contributions: [ProfileContribution]
        let meta: Meta?
        let summary: Summary

        struct Meta: Decodable { let generatedAt: String? }
        struct Summary: Decodable {
            let totalTokens: Double
            let totalCost: Double
        }
    }

    private let runner: ProcessRunning
    private let timeout: TimeInterval
    private let decoder = JSONDecoder()

    init(runner: ProcessRunning, timeout: TimeInterval = 300) {
        self.runner = runner
        self.timeout = timeout
    }

    func fetchDashboardBatch(_ request: DashboardSourceRequest) async throws -> DashboardSourceBatch {
        guard case let .local(context, now) = request else { throw DashboardSourceError.invalidGraph }
        // Resolve the timezone first. Concurrent `npx --yes` processes can race the package
        // installation cache when this Tokscale version has not been used on the machine yet.
        let timezoneResult = try await run(.configuredTimezone, context: context)
        let graphResult = try await run(.graph, context: context)

        let timezoneName = timezoneResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        guard let timezone = TimeZone(identifier: timezoneName) else {
            throw DashboardSourceError.invalidTimezone
        }
        let graph: GraphExport
        do {
            graph = try decoder.decode(GraphExport.self, from: Data(graphResult.stdout.utf8))
        } catch {
            throw DashboardSourceError.incompatibleCLI(
                version: context.version,
                detail: "graph JSON 结构与 TokChan 不兼容。"
            )
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timezone
        let today = calendar.startOfDay(for: now)
        guard let weekStart = calendar.date(byAdding: .day, value: -6, to: today),
              let monthStart = calendar.date(byAdding: .day, value: -29, to: today) else {
            throw DashboardSourceError.invalidTimezone
        }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = timezone
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"

        let dated = try graph.contributions.map { contribution -> (Date, ProfileContribution) in
            guard Self.isValid(contribution),
                  let value = contribution.date,
                  let date = formatter.date(from: value) else {
                throw DashboardSourceError.invalidGraph
            }
            return (calendar.startOfDay(for: date), contribution)
        }
        guard Self.isValid(graph.summary, contributions: graph.contributions) else {
            throw DashboardSourceError.invalidGraph
        }
        let generatedAt = graph.meta?.generatedAt.flatMap(Self.parseISODate) ?? now
        let selections: [(ProfilePeriod, Date?)] = [(.all, nil), (.day, today), (.week, weekStart), (.month, monthStart)]
        var profiles: [ProfilePeriod: DashboardData] = [:]
        for (period, start) in selections {
            let selected = dated.filter { date, _ in
                guard let start else { return true }
                return date >= start && date <= today
            }.map(\.1)
            let rangeStart = start.map(formatter.string(from:))
                ?? dated.map(\.0).min().map(formatter.string(from:))
            let rangeEnd = period == .all
                ? dated.map(\.0).max().map(formatter.string(from:))
                : formatter.string(from: today)
            profiles[period] = makeProfile(
                period: period,
                contributions: selected,
                dateRange: ProfileDateRange(start: rangeStart, end: rangeEnd),
                updatedAt: generatedAt
            )
        }
        let warnings = Self.graphWarnings(from: graphResult.stderr)
        return try DashboardSourceBatch(
            source: .local,
            account: nil,
            profiles: profiles,
            warnings: warnings
        )
    }

    private func run(_ command: TokscaleCommand, context: TokscaleCommandContext) async throws -> ProcessOutput {
        let arguments: [String]
        do {
            arguments = try TokscaleCommandBuilder.arguments(version: context.version, command: command)
        } catch {
            throw error
        }
        let output = try await runner.run(executable: context.npxURL, arguments: arguments, timeout: timeout)
        guard output.exitCode == 0 else {
            let detail = String((output.stderr.isEmpty ? output.stdout : output.stderr).prefix(4_000))
            if detail.localizedCaseInsensitiveContains("unknown command")
                || detail.localizedCaseInsensitiveContains("unexpected argument") {
                throw DashboardSourceError.incompatibleCLI(version: context.version, detail: detail)
            }
            throw TokscaleCLIError.failed(exitCode: output.exitCode, message: detail)
        }
        return output
    }

    private func makeProfile(
        period: ProfilePeriod,
        contributions: [ProfileContribution],
        dateRange: ProfileDateRange,
        updatedAt: Date
    ) -> DashboardData {
        var breakdown = TokenBreakdown()
        var totalTokens = 0.0
        var totalCost = 0.0
        var activeDays = 0
        for contribution in contributions {
            let dayTokens = contribution.totals?.tokens ?? contribution.tokenBreakdown?.total ?? 0
            totalTokens += dayTokens
            totalCost += contribution.totals?.cost ?? 0
            if dayTokens > 0 { activeDays += 1 }
            if let value = contribution.tokenBreakdown {
                breakdown = TokenBreakdown(
                    input: breakdown.input + value.input,
                    output: breakdown.output + value.output,
                    cacheRead: breakdown.cacheRead + value.cacheRead,
                    cacheWrite: breakdown.cacheWrite + value.cacheWrite,
                    reasoning: breakdown.reasoning + value.reasoning
                )
            }
        }
        return DashboardData(
            period: period,
            dateRange: dateRange,
            breakdown: breakdown,
            totalTokens: totalTokens,
            totalCost: totalCost,
            activeDays: activeDays,
            updatedAt: updatedAt,
            clients: DashboardData.aggregateClients(
                from: contributions,
                profileTotalTokens: totalTokens
            )
        )
    }

    private static func isValid(_ contribution: ProfileContribution) -> Bool {
        guard let totals = contribution.totals,
              let breakdown = contribution.tokenBreakdown,
              isNonnegativeFinite(totals.tokens),
              isNonnegativeFinite(totals.cost),
              isValid(breakdown),
              approximatelyEqual(totals.tokens, breakdown.total) else { return false }
        guard contribution.clients.allSatisfy({ client in
            !client.client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                && isValid(client.tokens)
                && isNonnegativeFinite(client.cost)
                && ((!client.models.isEmpty) || !(client.modelId ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                && client.models.allSatisfy { modelID, model in
                    !modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        && isNonnegativeFinite(model.tokens)
                        && isNonnegativeFinite(model.cost)
                }
        }) else { return false }
        return approximatelyEqual(
            contribution.clients.reduce(0) { $0 + $1.tokens.total },
            totals.tokens
        )
    }

    private static func isValid(_ summary: GraphExport.Summary, contributions: [ProfileContribution]) -> Bool {
        guard isNonnegativeFinite(summary.totalTokens),
              isNonnegativeFinite(summary.totalCost) else { return false }
        let contributionTokens = contributions.reduce(0) { $0 + ($1.totals?.tokens ?? 0) }
        let contributionCost = contributions.reduce(0) { $0 + ($1.totals?.cost ?? 0) }
        return approximatelyEqual(summary.totalTokens, contributionTokens)
            && approximatelyEqual(summary.totalCost, contributionCost)
    }

    private static func isValid(_ breakdown: TokenBreakdown) -> Bool {
        [breakdown.input, breakdown.output, breakdown.cacheRead, breakdown.cacheWrite, breakdown.reasoning]
            .allSatisfy(isNonnegativeFinite)
    }

    private static func isNonnegativeFinite(_ value: Double) -> Bool {
        value.isFinite && value >= 0
    }

    private static func approximatelyEqual(_ lhs: Double, _ rhs: Double) -> Bool {
        let scale = max(abs(lhs), abs(rhs), 1)
        return abs(lhs - rhs) <= scale * 1e-9
    }

    private static func graphWarnings(from diagnostics: String) -> [String] {
        let normalized = diagnostics.lowercased()
        guard normalized.contains("unpriced")
                || normalized.contains("missing pricing")
                || normalized.contains("pricing data is unavailable")
                || normalized.contains("pricing is unavailable")
                || normalized.contains("cost-incomplete") else { return [] }
        return ["Tokscale 报告部分模型缺少价格，本次成本可能不完整。"]
    }

    private static func parseISODate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }
}

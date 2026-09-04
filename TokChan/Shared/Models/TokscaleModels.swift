import Foundation

enum ProfilePeriod: String, Codable, CaseIterable, Identifiable {
    case all, day, week, month

    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: return "全部"
        case .day: return "日"
        case .week: return "周"
        case .month: return "月"
        }
    }
}

struct ProfileDateRange: Codable, Equatable {
    let start: String?
    let end: String?

    var displayText: String {
        guard let start, let end else { return "暂无日期范围" }
        return "\(start) – \(end)"
    }
}

struct PublicProfileResponse: Decodable {
    let period: ProfilePeriod?
    let dateRange: ProfileDateRange?
    let user: ProfileUser
    let stats: ProfileStats
    let updatedAt: String?
    let contributions: [ProfileContribution]
}

struct ProfileUser: Decodable {
    let username: String
    let displayName: String?
    let avatarUrl: URL?
    let rank: Int?
}

struct ProfileStats: Decodable {
    let totalTokens: Double
    let totalCost: Double
    let activeDays: Int
    let inputTokens: Double?
    let outputTokens: Double?
    let cacheReadTokens: Double?
    let cacheWriteTokens: Double?
    let reasoningTokens: Double?

    var breakdown: TokenBreakdown? {
        guard let inputTokens, let outputTokens, let cacheReadTokens,
              let cacheWriteTokens, let reasoningTokens else { return nil }
        return TokenBreakdown(input: inputTokens, output: outputTokens,
                              cacheRead: cacheReadTokens, cacheWrite: cacheWriteTokens,
                              reasoning: reasoningTokens)
    }
}

struct ProfileDailyTotals: Decodable {
    let tokens: Double
    let cost: Double
}

struct ProfileContribution: Decodable {
    let date: String?
    let totals: ProfileDailyTotals?
    let tokenBreakdown: TokenBreakdown?
    let clients: [ProfileClientRecord]
}

struct ProfileClientRecord: Decodable {
    let client: String
    let modelId: String?
    let models: [String: ProfileModelRecord]
    let tokens: TokenBreakdown
    let cost: Double

    private enum CodingKeys: String, CodingKey {
        case client, modelId, models, tokens, cost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        client = try container.decode(String.self, forKey: .client)
        modelId = try container.decodeIfPresent(String.self, forKey: .modelId)
        models = try container.decodeIfPresent([String: ProfileModelRecord].self, forKey: .models) ?? [:]
        tokens = try container.decodeIfPresent(TokenBreakdown.self, forKey: .tokens) ?? TokenBreakdown()
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
    }
}

struct ProfileModelRecord: Decodable {
    let tokens: Double
    let cost: Double

    private enum CodingKeys: String, CodingKey {
        case tokens, cost, input, output, cacheRead, cacheWrite, reasoning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        let output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        let cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        let cacheWrite = try container.decodeIfPresent(Double.self, forKey: .cacheWrite) ?? 0
        let reasoning = try container.decodeIfPresent(Double.self, forKey: .reasoning) ?? 0
        tokens = try container.decodeIfPresent(Double.self, forKey: .tokens)
            ?? (input + output + cacheRead + cacheWrite + reasoning)
        cost = try container.decodeIfPresent(Double.self, forKey: .cost) ?? 0
    }
}

struct TokenBreakdown: Codable, Equatable {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
    let reasoning: Double

    var total: Double {
        input + output + cacheRead + cacheWrite + reasoning
    }

    init(
        input: Double = 0,
        output: Double = 0,
        cacheRead: Double = 0,
        cacheWrite: Double = 0,
        reasoning: Double = 0
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite = cacheWrite
        self.reasoning = reasoning
    }

    private enum CodingKeys: String, CodingKey {
        case input, output, cacheRead, cacheWrite, reasoning
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Double.self, forKey: .input) ?? 0
        output = try container.decodeIfPresent(Double.self, forKey: .output) ?? 0
        cacheRead = try container.decodeIfPresent(Double.self, forKey: .cacheRead) ?? 0
        cacheWrite = try container.decodeIfPresent(Double.self, forKey: .cacheWrite) ?? 0
        reasoning = try container.decodeIfPresent(Double.self, forKey: .reasoning) ?? 0
    }
}

struct DashboardData: Codable, Equatable {
    let period: ProfilePeriod
    let dateRange: ProfileDateRange?
    let breakdown: TokenBreakdown?
    let username: String
    let displayName: String
    let avatarURL: URL?
    let rank: Int?
    let totalTokens: Double
    let totalCost: Double
    let activeDays: Int
    let updatedAt: Date?
    let clients: [ClientUsageGroup]

    init(response: PublicProfileResponse) {
        period = response.period ?? .all
        dateRange = response.dateRange
        breakdown = response.stats.breakdown
        username = response.user.username
        if let candidate = response.user.displayName, !candidate.isEmpty {
            displayName = candidate
        } else {
            displayName = response.user.username
        }
        avatarURL = response.user.avatarUrl
        rank = response.user.rank
        totalTokens = response.stats.totalTokens
        totalCost = response.stats.totalCost
        activeDays = response.stats.activeDays
        updatedAt = response.updatedAt.flatMap(Self.parseDate)
        clients = Self.aggregateClients(
            from: response.contributions,
            profileTotalTokens: response.stats.totalTokens
        )
    }

    static func day(from response: PublicProfileResponse) throws -> DashboardData {
        // Use the server's date boundary and daily bucket, never the viewer's timezone.
        guard let date = response.dateRange?.end else { throw TokscaleAPIError.invalidResponse }
        let contribution = response.contributions.first { $0.date == date }
        let total = contribution?.totals?.tokens ?? 0
        let breakdown = contribution == nil ? TokenBreakdown() : contribution?.tokenBreakdown
        let daily = PublicProfileResponse(
            period: .day, dateRange: ProfileDateRange(start: date, end: date),
            user: ProfileUser(username: response.user.username, displayName: response.user.displayName,
                              avatarUrl: response.user.avatarUrl, rank: nil),
            stats: ProfileStats(totalTokens: total, totalCost: contribution?.totals?.cost ?? 0,
                activeDays: total > 0 ? 1 : 0, inputTokens: breakdown?.input,
                outputTokens: breakdown?.output, cacheReadTokens: breakdown?.cacheRead,
                cacheWriteTokens: breakdown?.cacheWrite, reasoningTokens: breakdown?.reasoning),
            updatedAt: response.updatedAt, contributions: contribution.map { [$0] } ?? [])
        return DashboardData(response: daily)
    }

    private static func parseDate(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value) ?? ISO8601DateFormatter().date(from: value)
    }

    private static func aggregateClients(
        from contributions: [ProfileContribution],
        profileTotalTokens: Double
    ) -> [ClientUsageGroup] {
        struct ModelAccumulator {
            var tokens = 0.0
            var cost = 0.0
        }

        struct ClientAccumulator {
            var tokens = 0.0
            var cost = 0.0
            var models: [String: ModelAccumulator] = [:]
        }

        var grouped: [String: ClientAccumulator] = [:]
        for contribution in contributions {
            for client in contribution.clients {
                var clientAccumulator = grouped[client.client] ?? ClientAccumulator()
                clientAccumulator.tokens += client.tokens.total
                clientAccumulator.cost += client.cost

                if client.models.isEmpty, let modelID = client.modelId, !modelID.isEmpty {
                    var model = clientAccumulator.models[modelID] ?? ModelAccumulator()
                    model.tokens += client.tokens.total
                    model.cost += client.cost
                    clientAccumulator.models[modelID] = model
                } else {
                    for (modelID, metrics) in client.models {
                        var model = clientAccumulator.models[modelID] ?? ModelAccumulator()
                        model.tokens += metrics.tokens
                        model.cost += metrics.cost
                        clientAccumulator.models[modelID] = model
                    }
                }

                grouped[client.client] = clientAccumulator
            }
        }

        var result: [ClientUsageGroup] = []
        for (clientID, value) in grouped {
            var models: [ModelUsage] = []
            for (modelID, metrics) in value.models {
                models.append(ModelUsage(id: modelID, tokens: metrics.tokens, cost: metrics.cost))
            }
            models.sort(by: modelSort)

            result.append(ClientUsageGroup(
                id: clientID,
                tokens: value.tokens,
                cost: value.cost,
                percentage: profileTotalTokens > 0 ? value.tokens / profileTotalTokens : 0,
                models: models
            ))
        }
        result.sort(by: clientSort)
        return result
    }

    private static func modelSort(_ lhs: ModelUsage, _ rhs: ModelUsage) -> Bool {
        lhs.tokens == rhs.tokens ? lhs.id < rhs.id : lhs.tokens > rhs.tokens
    }

    private static func clientSort(_ lhs: ClientUsageGroup, _ rhs: ClientUsageGroup) -> Bool {
        lhs.tokens == rhs.tokens ? lhs.id < rhs.id : lhs.tokens > rhs.tokens
    }
}

struct ClientUsageGroup: Codable, Identifiable, Equatable {
    let id: String
    let tokens: Double
    let cost: Double
    let percentage: Double
    let models: [ModelUsage]
}

struct ModelUsage: Codable, Identifiable, Equatable {
    let id: String
    let tokens: Double
    let cost: Double
}

// Fixed order is shared by the proportional bar and its accessible legend.
enum TokenCategory: String, CaseIterable, Identifiable {
    case input = "Input"
    case output = "Output"
    case cacheRead = "Cache Read"
    case cacheWrite = "Cache Write"
    case reasoning = "Reasoning"
    var id: String { rawValue }
}

extension TokenBreakdown {
    func value(for category: TokenCategory) -> Double {
        let value: Double
        switch category {
        case .input: value = input
        case .output: value = output
        case .cacheRead: value = cacheRead
        case .cacheWrite: value = cacheWrite
        case .reasoning: value = reasoning
        }
        return value.isFinite ? max(0, value) : 0
    }

    func fraction(for category: TokenCategory) -> Double {
        let values = TokenCategory.allCases.map { value(for: $0) }
        // Normalize before summation so even very large inputs cannot overflow.
        guard let largest = values.max(), largest > 0 else { return 0 }
        let denominator = values.reduce(0) { $0 + $1 / largest }
        return (value(for: category) / largest) / denominator
    }
}

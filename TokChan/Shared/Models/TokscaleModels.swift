import Foundation

struct PublicProfileResponse: Decodable {
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
}

struct ProfileContribution: Decodable {
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

struct TokenBreakdown: Decodable {
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

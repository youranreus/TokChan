import Foundation

enum DashboardDisplayFilter {
    static func clients(
        from sourceClients: [ClientUsageGroup],
        preferences: UserPreferences
    ) -> [ClientUsageGroup] {
        sourceClients.compactMap { client in
            if preferences.hiddenClientsEnabled,
               preferences.hiddenClientIDs.contains(client.id) {
                return nil
            }
            guard preferences.hideZeroCostModels else { return client }
            return ClientUsageGroup(
                id: client.id,
                tokens: client.tokens,
                cost: client.cost,
                percentage: client.percentage,
                models: client.models.filter { $0.cost != 0 }
            )
        }
    }
}

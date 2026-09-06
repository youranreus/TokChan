import Foundation

enum StatusItemTextRenderer {
    static func render(template: String, data: DashboardData) -> String {
        template
            .replacingOccurrences(
                of: "{token}",
                with: DisplayFormatters.compactNumber(data.totalTokens)
            )
            .replacingOccurrences(
                of: "{cost}",
                with: DisplayFormatters.currency(data.totalCost)
            )
    }
}

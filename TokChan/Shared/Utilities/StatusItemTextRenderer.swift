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
                with: statusItemCurrency(data.totalCost)
            )
    }

    private static func statusItemCurrency(_ value: Double) -> String {
        value.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(value >= 1_000 ? 0 : 2))
                .locale(Locale(identifier: "en_US"))
        )
    }
}

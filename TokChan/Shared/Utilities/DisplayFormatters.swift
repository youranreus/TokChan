import Foundation

enum DisplayFormatters {
    static func compactNumber(_ value: Double) -> String {
        let absolute = abs(value)
        let divisor: Double
        let suffix: String

        switch absolute {
        case 1_000_000_000_000...:
            divisor = 1_000_000_000_000
            suffix = "T"
        case 1_000_000_000...:
            divisor = 1_000_000_000
            suffix = "B"
        case 1_000_000...:
            divisor = 1_000_000
            suffix = "M"
        case 1_000...:
            divisor = 1_000
            suffix = "K"
        default:
            return value.formatted(.number.precision(.fractionLength(0)))
        }

        let scaled = value / divisor
        return scaled.formatted(.number.precision(.fractionLength(scaled >= 100 ? 0 : 1))) + suffix
    }

    static func currency(_ value: Double) -> String {
        value.formatted(
            .currency(code: "USD")
                .precision(.fractionLength(value >= 1_000 ? 0 : 2))
        )
    }

    static func percentage(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(1)))
    }

    static func relativeDate(_ date: Date?) -> String {
        guard let date else { return "从未" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    static func interval(minutes: Int) -> String {
        if minutes.isMultiple(of: 1_440) {
            let days = minutes / 1_440
            return days == 1 ? "每天" : "每 \(days) 天"
        }
        if minutes.isMultiple(of: 60) {
            let hours = minutes / 60
            return hours == 1 ? "每小时" : "每 \(hours) 小时"
        }
        return "每 \(minutes) 分钟"
    }
}

import Foundation

/// Produces the single freshness description shared by the dashboard and status menu.
enum SnapshotFreshnessFormatter {
    static func text(
        fetchedAt: Date?,
        dataDate: String?,
        now: Date = Date(),
        locale: Locale = Locale(identifier: "zh_CN"),
        calendar: Calendar = .current
    ) -> String? {
        guard let fetchedAt else { return nil }

        let relativeFormatter = RelativeDateTimeFormatter()
        relativeFormatter.locale = locale
        relativeFormatter.unitsStyle = .short
        let fetched = "更新于 \(relativeFormatter.localizedString(for: fetchedAt, relativeTo: now))"

        guard let dataDate else { return fetched }
        var gregorianCalendar = Calendar(identifier: .gregorian)
        gregorianCalendar.timeZone = calendar.timeZone

        let dayFormatter = DateFormatter()
        dayFormatter.locale = Locale(identifier: "en_US_POSIX")
        dayFormatter.calendar = gregorianCalendar
        dayFormatter.timeZone = gregorianCalendar.timeZone
        dayFormatter.dateFormat = "yyyy-MM-dd"
        guard dataDate != dayFormatter.string(from: now) else { return fetched }
        return "数据日期 \(dataDate) · \(fetched)"
    }
}

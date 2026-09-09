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

        // "读取" describes the client's last successful read; it never implies the server
        // has already aggregated a just-submitted upload.
        let fetched: String
        let age = now.timeIntervalSince(fetchedAt)
        if age < 60 {
            // A sub-minute age rounds to "0 秒", and a clock rollback makes it negative, so
            // RelativeDateTimeFormatter would render the read as happening in the future.
            fetched = "统计刚刚读取"
        } else {
            let relativeFormatter = RelativeDateTimeFormatter()
            relativeFormatter.locale = locale
            relativeFormatter.unitsStyle = .short
            fetched = "统计读取于 \(relativeFormatter.localizedString(for: fetchedAt, relativeTo: now))"
        }

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

import Foundation

struct AutosubmitStatus: Codable, Equatable {
    let enabled: Bool
    let intervalMinutes: Int
    let scheduler: String?
    let clients: [String]
    let since: String?
    let until: String?
    let year: String?
    let today: Bool
    let yesterday: Bool
    let week: Bool
    let month: Bool
    let managedExecutable: String?
    let managedExecutableVersion: String?
    let managedExecutableStale: Bool
    let lastRunAtMs: Double?
    let lastError: String?

    var lastRunAt: Date? {
        lastRunAtMs.map { Date(timeIntervalSince1970: $0 / 1_000) }
    }

    var filterKind: AutosubmitFilterKind {
        if today { return .today }
        if yesterday { return .yesterday }
        if week { return .week }
        if month { return .month }
        if year != nil { return .year }
        if since != nil || until != nil { return .range }
        return .all
    }

    var dateFilterSummary: String {
        switch filterKind {
        case .all:
            return "全部时间"
        case .today:
            return "今天"
        case .yesterday:
            return "昨天"
        case .week:
            return "最近 7 天"
        case .month:
            return "本月"
        case .year:
            return year.map { "\($0) 年" } ?? "指定年份"
        case .range:
            switch (since, until) {
            case let (.some(start), .some(end)):
                return "\(start) – \(end)"
            case let (.some(start), .none):
                return "自 \(start) 起"
            case let (.none, .some(end)):
                return "截至 \(end)"
            case (.none, .none):
                return "日期范围"
            }
        }
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, intervalMinutes, scheduler, clients, since, until, year
        case today, yesterday, week, month
        case managedExecutable, managedExecutableVersion, managedExecutableStale
        case lastRunAtMs, lastError
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        intervalMinutes = try container.decodeIfPresent(Int.self, forKey: .intervalMinutes) ?? 1_440
        scheduler = try container.decodeIfPresent(String.self, forKey: .scheduler)
        clients = try container.decodeIfPresent([String].self, forKey: .clients) ?? []
        since = try container.decodeIfPresent(String.self, forKey: .since)
        until = try container.decodeIfPresent(String.self, forKey: .until)
        year = try container.decodeIfPresent(String.self, forKey: .year)
        today = try container.decodeIfPresent(Bool.self, forKey: .today) ?? false
        yesterday = try container.decodeIfPresent(Bool.self, forKey: .yesterday) ?? false
        week = try container.decodeIfPresent(Bool.self, forKey: .week) ?? false
        month = try container.decodeIfPresent(Bool.self, forKey: .month) ?? false
        managedExecutable = try container.decodeIfPresent(String.self, forKey: .managedExecutable)
        managedExecutableVersion = try container.decodeIfPresent(String.self, forKey: .managedExecutableVersion)
        managedExecutableStale = try container.decodeIfPresent(Bool.self, forKey: .managedExecutableStale) ?? false
        lastRunAtMs = try container.decodeIfPresent(Double.self, forKey: .lastRunAtMs)
        lastError = try container.decodeIfPresent(String.self, forKey: .lastError)
    }
}

enum AutosubmitFilterKind: String, CaseIterable, Identifiable {
    case all
    case today
    case yesterday
    case week
    case month
    case year
    case range

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部时间"
        case .today: return "今天"
        case .yesterday: return "昨天"
        case .week: return "最近 7 天"
        case .month: return "本月"
        case .year: return "指定年份"
        case .range: return "日期范围"
        }
    }
}

struct AutosubmitConfiguration: Equatable {
    var enabled: Bool
    var intervalMinutes: Int
    var clients: [String]
    var filterKind: AutosubmitFilterKind
    var year: String
    var since: String
    var until: String
}

extension AutosubmitConfiguration {
    init(status: AutosubmitStatus) {
        enabled = status.enabled
        intervalMinutes = status.intervalMinutes
        clients = status.clients
        filterKind = status.filterKind
        year = status.year ?? ""
        since = status.since ?? ""
        until = status.until ?? ""
    }
}

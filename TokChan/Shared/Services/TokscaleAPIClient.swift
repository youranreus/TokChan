import Foundation

private extension CharacterSet {
    static let urlPathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}

protocol TokscaleAPIService {
    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch
}

struct DashboardProfileBatch: Equatable {
    let username: String
    let profiles: [ProfilePeriod: DashboardData]

    init(username: String, profiles: [ProfilePeriod: DashboardData]) throws {
        let expected = Set(ProfilePeriod.allCases)
        guard Set(profiles.keys) == expected,
              profiles.values.allSatisfy({
                  $0.username.caseInsensitiveCompare(username) == .orderedSame
              }) else {
            throw TokscaleAPIError.invalidResponse
        }
        for period in ProfilePeriod.allCases where profiles[period]?.period != period {
            throw TokscaleAPIError.mismatchedPeriod
        }
        self.username = username
        self.profiles = profiles
    }
}

enum TokscaleAPIError: LocalizedError {
    case invalidUsername
    case invalidResponse
    case mismatchedPeriod
    case profileNotFound
    case server(statusCode: Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "请在设置中填写有效的 Tokscale 用户名。"
        case .mismatchedPeriod:
            return "Tokscale 返回的时间范围不一致，请重试。"
        case .invalidResponse:
            return "Tokscale 返回了无效响应。"
        case .profileNotFound:
            return "未找到该 Tokscale 资料，请先提交用量或检查用户名。"
        case let .server(statusCode):
            return "Tokscale 请求失败，HTTP 状态码为 \(statusCode)。"
        case let .decoding(error):
            return "无法解析 Tokscale 数据：\(error.localizedDescription)"
        }
    }
}

final class LiveTokscaleAPIClient: TokscaleAPIService {
    private let session: URLSession
    private let baseURL: URL
    private let decoder: JSONDecoder

    init(
        session: URLSession = .shared,
        // This compile-time constant is part of the verified Tokscale API contract.
        baseURL: URL = URL(string: "https://tokscale.ai/api/users")!
    ) {
        self.session = session
        self.baseURL = baseURL
        decoder = JSONDecoder()
    }

    func fetchDashboardBatch(username: String) async throws -> DashboardProfileBatch {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TokscaleAPIError.invalidUsername }

        async let allResponse = fetchResponse(username: trimmed, period: .all)
        async let weekResponse = fetchResponse(username: trimmed, period: .week)
        async let monthResponse = fetchResponse(username: trimmed, period: .month)
        let (all, week, month) = try await (allResponse, weekResponse, monthResponse)
        let profiles: [ProfilePeriod: DashboardData] = [
            .all: DashboardData(response: all),
            .day: try DashboardData.day(from: week),
            .week: DashboardData(response: week),
            .month: DashboardData(response: month)
        ]
        return try DashboardProfileBatch(username: trimmed, profiles: profiles)
    }

    // Kept as a focused seam for period mapping tests and future single-response diagnostics.
    func fetchProfile(username: String, period: ProfilePeriod) async throws -> DashboardData {
        let remotePeriod: ProfilePeriod = period == .day ? .week : period
        let response = try await fetchResponse(username: username, period: remotePeriod)
        return try period == .day ? DashboardData.day(from: response) : DashboardData(response: response)
    }

    private func fetchResponse(username: String, period: ProfilePeriod) async throws -> PublicProfileResponse {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TokscaleAPIError.invalidUsername }

        guard let encodedUsername = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathSegmentAllowed) else {
            throw TokscaleAPIError.invalidUsername
        }
        let baseString = baseURL.absoluteString.hasSuffix("/") ? baseURL.absoluteString : "\(baseURL.absoluteString)/"
        guard let url = URL(string: baseString + encodedUsername) else {
            throw TokscaleAPIError.invalidUsername
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw TokscaleAPIError.invalidUsername
        }
        components.queryItems = [URLQueryItem(name: "period", value: period.rawValue)]
        guard let requestURL = components.url else { throw TokscaleAPIError.invalidUsername }
        var request = URLRequest(
            url: requestURL,
            cachePolicy: .reloadRevalidatingCacheData,
            timeoutInterval: 30
        )
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TokscaleAPIError.invalidResponse
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 404:
            throw TokscaleAPIError.profileNotFound
        default:
            throw TokscaleAPIError.server(statusCode: httpResponse.statusCode)
        }

        do {
            let profile = try decoder.decode(PublicProfileResponse.self, from: data)
            guard profile.period == period else { throw TokscaleAPIError.mismatchedPeriod }
            return profile
        } catch let error as TokscaleAPIError {
            throw error
        } catch {
            throw TokscaleAPIError.decoding(error)
        }
    }
}

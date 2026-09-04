import Foundation

private extension CharacterSet {
    static let urlPathSegmentAllowed: CharacterSet = {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return allowed
    }()
}

protocol TokscaleAPIService {
    func fetchProfile(username: String, period: ProfilePeriod) async throws -> DashboardData
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

    func fetchProfile(username: String, period: ProfilePeriod) async throws -> DashboardData {
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
        let remotePeriod: ProfilePeriod = period == .day ? .week : period
        components.queryItems = [URLQueryItem(name: "period", value: remotePeriod.rawValue)]
        guard let requestURL = components.url else { throw TokscaleAPIError.invalidUsername }
        let (data, response) = try await session.data(from: requestURL)
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
            guard profile.period == remotePeriod else { throw TokscaleAPIError.mismatchedPeriod }
            return try period == .day ? DashboardData.day(from: profile) : DashboardData(response: profile)
        } catch {
            throw TokscaleAPIError.decoding(error)
        }
    }
}

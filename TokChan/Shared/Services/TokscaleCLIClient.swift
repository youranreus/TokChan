import Foundation

struct TokscaleCommandContext: Equatable {
    let npxURL: URL
    let version: String
}

enum TokscaleCommand: Equatable {
    case whoami
    case submit
    case autosubmitStatus
    case configureAutosubmit(AutosubmitConfiguration)
    case disableAutosubmit
    case runAutosubmitNow
}

enum TokscaleCommandBuilder {
    static func arguments(version: String, command: TokscaleCommand) throws -> [String] {
        guard isValidVersion(version) else { throw TokscaleCLIError.invalidVersion }
        var arguments = ["--yes", "tokscale@\(version)"]

        switch command {
        case .whoami:
            arguments += ["whoami"]
        case .submit:
            arguments += ["submit"]
        case .autosubmitStatus:
            arguments += ["autosubmit", "status", "--json"]
        case let .configureAutosubmit(configuration):
            arguments += try configurationArguments(configuration)
        case .disableAutosubmit:
            arguments += ["autosubmit", "disable"]
        case .runAutosubmitNow:
            arguments += ["autosubmit", "run", "--force"]
        }

        return arguments
    }

    static func isValidVersion(_ version: String) -> Bool {
        version.range(
            of: #"^(latest|[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?)$"#,
            options: .regularExpression
        ) != nil
    }

    private static func configurationArguments(
        _ configuration: AutosubmitConfiguration
    ) throws -> [String] {
        guard (1...525_600).contains(configuration.intervalMinutes) else {
            throw TokscaleCLIError.invalidInterval
        }

        var arguments = [
            "autosubmit", "enable",
            "--interval", "\(configuration.intervalMinutes)m"
        ]

        let clients = configuration.clients
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let clientPattern = #"^[a-z0-9][a-z0-9-]*$"#
        guard clients.allSatisfy({ $0.range(of: clientPattern, options: .regularExpression) != nil }) else {
            throw TokscaleCLIError.invalidClient
        }
        if !clients.isEmpty {
            arguments += ["--client", clients.joined(separator: ",")]
        }

        switch configuration.filterKind {
        case .all:
            break
        case .today:
            arguments.append("--today")
        case .yesterday:
            arguments.append("--yesterday")
        case .week:
            arguments.append("--week")
        case .month:
            arguments.append("--month")
        case .year:
            guard configuration.year.range(of: #"^[0-9]{4}$"#, options: .regularExpression) != nil,
                  let year = Int(configuration.year), year > 0 else {
                throw TokscaleCLIError.invalidDateFilter
            }
            arguments += ["--year", configuration.year]
        case .range:
            guard !configuration.since.isEmpty || !configuration.until.isEmpty else {
                throw TokscaleCLIError.invalidDateFilter
            }
            var sinceDate: Date?
            var untilDate: Date?
            if !configuration.since.isEmpty {
                guard let date = parsedDate(configuration.since) else {
                    throw TokscaleCLIError.invalidDateFilter
                }
                sinceDate = date
                arguments += ["--since", configuration.since]
            }
            if !configuration.until.isEmpty {
                guard let date = parsedDate(configuration.until) else {
                    throw TokscaleCLIError.invalidDateFilter
                }
                untilDate = date
                arguments += ["--until", configuration.until]
            }
            if let sinceDate, let untilDate, sinceDate > untilDate {
                throw TokscaleCLIError.invalidDateFilter
            }
        }

        return arguments
    }

    private static func parsedDate(_ value: String) -> Date? {
        guard value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}$"#, options: .regularExpression) != nil else {
            return nil
        }

        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        let components = DateComponents(year: parts[0], month: parts[1], day: parts[2])
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == parts[0], resolved.month == parts[1], resolved.day == parts[2] else {
            return nil
        }
        return date
    }
}

struct ProcessOutput: Equatable {
    let exitCode: Int32
    let stdout: String
    let stderr: String
}

protocol ProcessRunning {
    func run(executable: URL, arguments: [String], timeout: TimeInterval) async throws -> ProcessOutput
}

enum ProcessRunnerError: LocalizedError {
    case timedOut
    case unreadableOutput

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Tokscale 运行超时，已停止该进程。"
        case .unreadableOutput:
            return "Tokscale 返回了无法读取的输出。"
        }
    }
}

final class FoundationProcessRunner: ProcessRunning {
    func run(
        executable: URL,
        arguments: [String],
        timeout: TimeInterval
    ) async throws -> ProcessOutput {
        try await withThrowingTaskGroup(of: ProcessOutput.self) { group in
            group.addTask {
                try await self.runUntilExit(executable: executable, arguments: arguments)
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw ProcessRunnerError.timedOut
            }

            guard let result = try await group.next() else {
                throw ProcessRunnerError.unreadableOutput
            }
            group.cancelAll()
            return result
        }
    }

    private func runUntilExit(executable: URL, arguments: [String]) async throws -> ProcessOutput {
        let process = Process()
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.environment = Self.environment(for: executable)

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()

            let stdoutTask = Task { try stdoutPipe.fileHandleForReading.readToEnd() }
            let stderrTask = Task { try stderrPipe.fileHandleForReading.readToEnd() }
            let exitCode = try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Int32, Error>) in
                process.terminationHandler = { finishedProcess in
                    continuation.resume(returning: finishedProcess.terminationStatus)
                }

                do {
                    try process.run()
                } catch {
                    process.terminationHandler = nil
                    stdoutPipe.fileHandleForWriting.closeFile()
                    stderrPipe.fileHandleForWriting.closeFile()
                    continuation.resume(throwing: error)
                }
            }
            let stdoutResult = try await stdoutTask.value
            let stderrResult = try await stderrTask.value

            return ProcessOutput(
                exitCode: exitCode,
                stdout: Self.decode(stdoutResult ?? Data()),
                stderr: Self.decode(stderrResult ?? Data())
            )
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func decode(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    private static func environment(for executable: URL) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let executableDirectory = executable.deletingLastPathComponent().path
        let inheritedPath = environment["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        let pathEntries = inheritedPath.split(separator: ":").map(String.init)
        if !pathEntries.contains(executableDirectory) {
            environment["PATH"] = ([executableDirectory] + pathEntries).joined(separator: ":")
        }
        return environment
    }
}

protocol TokscaleCLIService {
    func whoAmI(context: TokscaleCommandContext) async throws -> String
    func submit(context: TokscaleCommandContext) async throws
    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus
    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws
    func disableAutosubmit(context: TokscaleCommandContext) async throws
    func runAutosubmitNow(context: TokscaleCommandContext) async throws
}

enum TokscaleCLIError: LocalizedError {
    case missingNpx
    case invalidVersion
    case invalidInterval
    case invalidClient
    case invalidDateFilter
    case failed(exitCode: Int32, message: String)
    case invalidStatusJSON(Error)
    case usernameNotFound

    var errorDescription: String? {
        switch self {
        case .missingNpx:
            return "找不到 npx，请在设置中选择其可执行文件。"
        case .invalidVersion:
            return "请填写 latest 或 4.15.0 这样的语义化版本号。"
        case .invalidInterval:
            return "自动提交间隔必须在 1 分钟到 365 天之间。"
        case .invalidClient:
            return "一个或多个 Tokscale 客户端标识无效。"
        case .invalidDateFilter:
            return "请输入有效年份或 YYYY-MM-DD 格式的日期。"
        case let .failed(exitCode, message):
            return "Tokscale 退出码为 \(exitCode)：\(message)"
        case let .invalidStatusJSON(error):
            return "无法读取自动提交状态：\(error.localizedDescription)"
        case .usernameNotFound:
            return "Tokscale 尚未登录，或无法识别当前用户名。"
        }
    }
}

final class TokscaleCLIClient: TokscaleCLIService {
    private let runner: ProcessRunning
    private let decoder = JSONDecoder()
    private let timeout: TimeInterval

    init(runner: ProcessRunning, timeout: TimeInterval = 300) {
        self.runner = runner
        self.timeout = timeout
    }

    func whoAmI(context: TokscaleCommandContext) async throws -> String {
        let output = try await run(.whoami, context: context)
        for line in output.stdout.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.lowercased().hasPrefix("username:") {
                let username = text.dropFirst("username:".count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !username.isEmpty { return username }
            }
        }
        throw TokscaleCLIError.usernameNotFound
    }

    func submit(context: TokscaleCommandContext) async throws {
        _ = try await run(.submit, context: context)
    }

    func autosubmitStatus(context: TokscaleCommandContext) async throws -> AutosubmitStatus {
        let output = try await run(.autosubmitStatus, context: context)
        guard let data = output.stdout.data(using: .utf8) else {
            throw ProcessRunnerError.unreadableOutput
        }
        do {
            return try decoder.decode(AutosubmitStatus.self, from: data)
        } catch {
            throw TokscaleCLIError.invalidStatusJSON(error)
        }
    }

    func configureAutosubmit(
        _ configuration: AutosubmitConfiguration,
        context: TokscaleCommandContext
    ) async throws {
        _ = try await run(.configureAutosubmit(configuration), context: context)
    }

    func disableAutosubmit(context: TokscaleCommandContext) async throws {
        _ = try await run(.disableAutosubmit, context: context)
    }

    func runAutosubmitNow(context: TokscaleCommandContext) async throws {
        _ = try await run(.runAutosubmitNow, context: context)
    }

    private func run(
        _ command: TokscaleCommand,
        context: TokscaleCommandContext
    ) async throws -> ProcessOutput {
        let arguments = try TokscaleCommandBuilder.arguments(
            version: context.version,
            command: command
        )
        let output = try await runner.run(
            executable: context.npxURL,
            arguments: arguments,
            timeout: timeout
        )
        guard output.exitCode == 0 else {
            let message = Self.sanitizedMessage(output.stderr.isEmpty ? output.stdout : output.stderr)
            throw TokscaleCLIError.failed(exitCode: output.exitCode, message: message)
        }
        return output
    }

    private static func sanitizedMessage(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "未提供错误详情。" }
        return String(trimmed.prefix(4_000))
    }
}

import SwiftUI

struct FirstUseOnboardingView: View {
    static let accountControlHeight: CGFloat = 32

    @ObservedObject var viewModel: DashboardViewModel
    @State private var usernameDraft: String

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
        _usernameDraft = State(initialValue: viewModel.preferences.username)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Spacer(minLength: 16)
            currentStep
            Spacer(minLength: 16)
            Text("稍后仍可在设置的“常规”页修改用户名。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("first-use-onboarding")
    }

    private var header: some View {
        VStack(spacing: 14) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 5) {
                Text("欢迎使用 TokChan")
                    .font(.title2.weight(.semibold))
                Text("两步连接 Tokscale，并显示你的用量。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            stepIndicator
        }
        .frame(maxWidth: .infinity)
    }

    private var stepIndicator: some View {
        HStack(spacing: 8) {
            stepBadge(number: 1, title: "连接账号", isActive: activeStep == 1)
            Rectangle()
                .fill(Color.secondary.opacity(0.25))
                .frame(width: 30, height: 1)
                .accessibilityHidden(true)
            stepBadge(number: 2, title: "首次提交", isActive: activeStep == 2)
        }
        .padding(.top, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("首次设置，第 \(activeStep) 步，共 2 步")
    }

    private func stepBadge(number: Int, title: String, isActive: Bool) -> some View {
        HStack(spacing: 5) {
            Text("\(number)")
                .font(.caption2.weight(.bold))
                .frame(width: 18, height: 18)
                .foregroundStyle(isActive ? Color.white : Color.secondary)
                .background(isActive ? Color.accentColor : Color.secondary.opacity(0.15), in: Circle())
            Text(title)
                .font(.caption.weight(isActive ? .semibold : .regular))
                .foregroundStyle(isActive ? .primary : .secondary)
        }
    }

    @ViewBuilder
    private var currentStep: some View {
        switch viewModel.firstUseOnboardingState {
        case .discoveringIdentity:
            progressCard(
                title: "正在识别 Tokscale 账号",
                detail: "检查本机现有的 Tokscale 登录信息…"
            )
        case let .usernameEntry(message):
            usernameEntry(message: message)
        case let .verifying(username):
            progressCard(
                title: "正在验证 @\(username)",
                detail: "正在强制读取全部范围统计…"
            )
        case let .firstSubmission(username, message):
            firstSubmission(username: username, message: message)
        case let .submitting(username):
            progressCard(
                title: "正在提交本地用量",
                detail: "提交完成后将重新验证 @\(username) 的统计。"
            )
        case .hidden:
            EmptyView()
        }
    }

    private func usernameEntry(message: String?) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text("连接 Tokscale 账号")
                    .font(.headline)
                Text("手工输入公开资料用户名，或读取本机 Tokscale 登录。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            TextField("Tokscale 用户名", text: $usernameDraft)
                .textFieldStyle(.roundedBorder)
                .controlSize(.large)
                .frame(height: Self.accountControlHeight)
                .disabled(viewModel.isPerformingOperation)
                .onSubmit(verifyUsername)
                .accessibilityLabel("Tokscale 用户名")
                .accessibilityIdentifier("onboarding-username-field")

            if let message {
                feedback(message)
            }

            HStack(spacing: 8) {
                Button {
                    verifyUsername()
                } label: {
                    Text("继续")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .frame(height: Self.accountControlHeight)
                .disabled(trimmedUsername.isEmpty || viewModel.isPerformingOperation)
                .keyboardShortcut(.defaultAction)
                .help(trimmedUsername.isEmpty ? "请输入 Tokscale 用户名" : "保存用户名并验证全部范围统计")
                .accessibilityIdentifier("onboarding-continue-button")

                Button {
                    Task { await viewModel.discoverIdentity() }
                } label: {
                    Text("识别本机登录")
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                }
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .frame(height: Self.accountControlHeight)
                .disabled(viewModel.isPerformingOperation)
                .help("通过 Tokscale CLI 读取本机已登录用户名")
                .accessibilityIdentifier("onboarding-discover-identity-button")
            }

            CursorLoginView(
                state: viewModel.cursorLoginState,
                isDisabled: viewModel.isPerformingOperation,
                login: { Task { await viewModel.loginCursor() } }
            )
            .padding(10)
            .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))

            Divider()

            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("还没有账号？")
                        .font(.callout.weight(.medium))
                    Text("前往 Tokscale 了解账号与登录方式。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                if let websiteURL = URL(string: "https://tokscale.ai") {
                    Link("访问官网", destination: websiteURL)
                        .accessibilityLabel("访问 Tokscale 官网")
                        .accessibilityIdentifier("onboarding-account-link")
                }
            }
        }
        .onAppear {
            usernameDraft = viewModel.preferences.username
        }
        .onChange(of: viewModel.preferences.username) { username in
            usernameDraft = username
        }
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func firstSubmission(username: String, message: String?) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("完成第一次提交")
                    .font(.headline)
                Text("@\(username) 暂无累计 Tokens。提交本机用量后，TokChan 会立即重新读取统计。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let message {
                feedback(message)
            }

            Button("提交本地用量") {
                Task { await viewModel.submitFirstUsage() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .keyboardShortcut(.defaultAction)
            .help("通过 Tokscale CLI 提交一次本地用量，然后重新读取统计")
            .accessibilityIdentifier("onboarding-submit-button")

            Button("修改用户名") {
                usernameDraft = viewModel.preferences.username
                viewModel.editOnboardingUsername()
            }
            .buttonStyle(.borderless)
            .frame(maxWidth: .infinity)
            .help("返回上一步修改 Tokscale 用户名")
            .accessibilityIdentifier("onboarding-edit-username-button")
        }
        .padding(18)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func progressCard(title: String, detail: String) -> some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text(title)
                .font(.headline)
                .multilineTextAlignment(.center)
            Text(detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("onboarding-progress")
    }

    private func feedback(_ message: String) -> some View {
        Label {
            Text(message)
                .lineLimit(4)
                .help(message)
                .textSelection(.enabled)
        } icon: {
            Image(systemName: "exclamationmark.circle.fill")
        }
        .font(.caption)
        .foregroundStyle(.orange)
        .accessibilityLabel(message)
        .accessibilityIdentifier("onboarding-message")
    }

    private var activeStep: Int {
        switch viewModel.firstUseOnboardingState {
        case .firstSubmission, .submitting: return 2
        case .discoveringIdentity, .usernameEntry, .verifying, .hidden: return 1
        }
    }

    private var trimmedUsername: String {
        usernameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func verifyUsername() {
        guard !trimmedUsername.isEmpty else { return }
        Task { await viewModel.saveAndVerifyUsername(usernameDraft) }
    }
}

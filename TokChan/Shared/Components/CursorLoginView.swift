import AppKit
import SwiftUI

struct CursorLoginView: View {
    let state: CursorLoginState
    let isDisabled: Bool
    var title = "Cursor 登录（可选）"
    var showsLoginButton = true
    var showsConnectedStatus = false
    var showsCheckingStatus = false
    let login: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                ClientIcon(clientID: "cursor")
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.callout.weight(.semibold))
                    Text("尝试读取 Cursor 桌面端现有会话，凭据由 Tokscale 管理。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                if showsConnectedStatus {
                    Label("已登录", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("cursor-status-connected")
                } else if showsCheckingStatus {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在检查 Cursor 登录状态")
                        .accessibilityIdentifier("cursor-status-checking")
                } else if showsLoginButton {
                    Button("自动登录") { login() }
                        .disabled(isDisabled || state.isLoggingIn)
                        .accessibilityIdentifier("cursor-login-button")
                }
            }

            feedback
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("cursor-login-module")
    }

    @ViewBuilder
    private var feedback: some View {
        switch state {
        case .idle:
            EmptyView()
        case .loggingIn:
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("正在通过 Tokscale 登录 Cursor…")
                    .font(.caption)
            }
            .accessibilityIdentifier("cursor-login-progress")
        case let .succeeded(message):
            Label(message, systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
                .accessibilityIdentifier("cursor-login-success")
        case let .failed(message, fallbackCommand):
            VStack(alignment: .leading, spacing: 6) {
                Label {
                    Text(message)
                        .lineLimit(3)
                        .help(message)
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)

                HStack(spacing: 6) {
                    Text(fallbackCommand)
                        .font(.caption2.monospaced())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                        .help(fallbackCommand)
                    Spacer(minLength: 4)
                    Button("复制命令") { copy(fallbackCommand) }
                        .controlSize(.small)
                        .accessibilityIdentifier("cursor-login-copy-command")
                }
            }
            .accessibilityIdentifier("cursor-login-failure")
        }
    }

    private func copy(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

struct SettingsCursorLoginView: View {
    let loginState: CursorLoginState
    let connectionState: CursorConnectionState
    let isDisabled: Bool
    let login: () -> Void
    let retryStatus: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CursorLoginView(
                state: loginState,
                isDisabled: isDisabled,
                title: "Cursor 登录",
                showsLoginButton: connectionState.showsLoginAction,
                showsConnectedStatus: connectionState == .loggedIn,
                showsCheckingStatus: connectionState == .checking,
                login: login
            )
            connectionFeedback
        }
    }

    @ViewBuilder
    private var connectionFeedback: some View {
        switch connectionState {
        case .idle:
            EmptyView()
        case .checking:
            EmptyView()
        case .loggedIn:
            EmptyView()
        case .needsLogin:
            EmptyView()
        case let .checkFailed(message):
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Label {
                    Text(message)
                        .lineLimit(3)
                        .help(message)
                } icon: {
                    Image(systemName: "exclamationmark.circle.fill")
                }
                .font(.caption)
                .foregroundStyle(.orange)
                .accessibilityIdentifier("cursor-status-check-failure")

                Spacer(minLength: 4)
                Button("重新检查") { retryStatus() }
                    .controlSize(.small)
                    .disabled(isDisabled)
                    .accessibilityIdentifier("cursor-status-retry-button")
            }
        }
    }
}

private extension CursorLoginState {
    var isLoggingIn: Bool {
        if case .loggingIn = self { return true }
        return false
    }
}

import SwiftUI

struct AutosubmitStatusView: View {
    @ObservedObject var viewModel: DashboardViewModel

    @ViewBuilder
    var body: some View {
        switch viewModel.autosubmitState {
        case .idle, .loading:
            panelCard {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("正在读取自动提交状态…").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        case let .failed(message):
            panelCard {
                ErrorStateView(title: "自动提交状态不可用", message: message) {
                    Task { await viewModel.load() }
                }
            }
        case let .loaded(status):
            panelCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Circle()
                            .fill(status.enabled ? Color.green : Color.secondary)
                            .frame(width: 8, height: 8)
                        Text("自动提交")
                            .font(.subheadline.weight(.semibold))
                        Text(status.enabled ? DisplayFormatters.interval(minutes: status.intervalMinutes) : "已关闭")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("立即运行") {
                            Task { await viewModel.runAutosubmitNow() }
                        }
                        .buttonStyle(.borderless)
                        .disabled(viewModel.operation.isRunning)
                        .help("使用已保存的自动提交配置运行")
                        .accessibilityIdentifier("autosubmit-run-now")
                    }

                    HStack(spacing: 8) {
                        Label(status.scheduler ?? "未知调度器", systemImage: "calendar.badge.clock")
                        if let version = status.managedExecutableVersion {
                            Label("v\(version)", systemImage: status.managedExecutableStale ? "exclamationmark.triangle" : "shippingbox")
                        }
                        Spacer()
                        Text("上次运行于 \(DisplayFormatters.relativeDate(status.lastRunAt))")
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                    if !status.clients.isEmpty {
                        Text("客户端：\(status.clients.joined(separator: ", "))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Label(status.dateFilterSummary, systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if let executable = status.managedExecutable, !executable.isEmpty {
                        Label(executable, systemImage: "terminal")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }

                    if let lastError = status.lastError, !lastError.isEmpty {
                        Label(lastError, systemImage: "exclamationmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading)
    }
}

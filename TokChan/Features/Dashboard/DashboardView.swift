import AppKit
import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(spacing: 12) {
                    profileContent
                    autosubmitContent
                    backgroundLoadBanner
                    operationBanner
                    usageContent
                }
                .padding(14)
            }

            footer
        }
        .frame(width: 380, height: 680)
        .background(.background)
        .accessibilityIdentifier("dashboard-panel")
        .task {
            await viewModel.load()
        }
    }

    @ViewBuilder
    private var profileContent: some View {
        switch viewModel.profileState {
        case .idle, .loading:
            panelCard {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取 Tokscale 资料…")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        case let .failed(message):
            panelCard {
                ErrorStateView(title: "资料暂不可用", message: message) {
                    Task { await viewModel.load() }
                }
            }
        case let .loaded(profile):
            VStack(spacing: 10) {
                header(profile)
                metrics(profile)
            }
        }
    }

    private func header(_ profile: DashboardData) -> some View {
        HStack(spacing: 10) {
            AsyncImage(url: profile.avatarURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.circle.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
            .frame(width: 34, height: 34)
            .clipShape(Circle())

            VStack(alignment: .leading, spacing: 1) {
                Text(profile.displayName)
                    .font(.headline)
                    .lineLimit(1)
                Text("@\(profile.username) · 线上更新于 \(DisplayFormatters.relativeDate(profile.updatedAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if viewModel.isRefreshing, viewModel.cacheSavedAt != nil {
                    Text("正在后台更新，当前显示缓存数据")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 8)

            if viewModel.isRefreshing {
                ProgressView()
                    .controlSize(.small)
                    .help("正在后台更新")
            }

            Button {
                Task { await viewModel.refresh() }
            } label: {
                if viewModel.operation == .submitting {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.operation.isRunning)
            .help("先提交本地用量，再刷新线上资料")
            .accessibilityLabel("提交并刷新")
        }
    }

    private func metrics(_ profile: DashboardData) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricView(title: "令牌数", value: DisplayFormatters.compactNumber(profile.totalTokens))
            MetricView(title: "成本", value: DisplayFormatters.currency(profile.totalCost))
            MetricView(title: "排名", value: profile.rank.map { "#\($0)" } ?? "—")
            MetricView(title: "活跃天数", value: "\(profile.activeDays)")
        }
    }

    @ViewBuilder
    private var autosubmitContent: some View {
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
                    openSettingsWindowOnLegacySystem()
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

    @ViewBuilder
    private var backgroundLoadBanner: some View {
        if let message = viewModel.loadErrorMessage,
           viewModel.profileState.loadedValue != nil || viewModel.autosubmitState.loadedValue != nil {
            StatusBanner(text: "后台更新失败：\(message)", color: .orange, showsProgress: false)
        }
    }

    @ViewBuilder
    private var operationBanner: some View {
        switch viewModel.operation {
        case .idle:
            EmptyView()
        case .submitting:
            StatusBanner(text: "正在提交本地用量…", color: .accentColor, showsProgress: true)
        case .runningAutosubmit:
            StatusBanner(text: "正在运行自动提交…", color: .accentColor, showsProgress: true)
        case .savingSettings:
            StatusBanner(text: "正在保存自动提交设置…", color: .accentColor, showsProgress: true)
        case let .succeeded(message):
            StatusBanner(text: message, color: .green, showsProgress: false)
        case let .failed(message):
            StatusBanner(text: message, color: .red, showsProgress: false)
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        if case let .loaded(profile) = viewModel.profileState {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("客户端用量")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("全部时间")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                if profile.clients.isEmpty {
                    panelCard {
                        Text("暂时没有已提交的客户端或模型明细。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    ForEach(profile.clients) { client in
                        ClientUsageView(client: client)
                    }
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            settingsButton

            Spacer()

            Button("退出 TokChan") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderless)
        }
        .font(.caption)
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Color.secondary.opacity(0.06))
    }

    @ViewBuilder
    private var settingsButton: some View {
        if #available(macOS 14.0, *) {
            SettingsLink {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("settings-button")
        } else {
            Button {
                openSettingsWindowOnLegacySystem()
            } label: {
                Label("设置", systemImage: "gearshape")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier("settings-button")
        }
    }

    private func openSettingsWindowOnLegacySystem() {
        NSApplication.shared.activate(ignoringOtherApps: true)
        let didOpen = NSApplication.shared.sendAction(
            Selector(("showSettingsWindow:")),
            to: nil,
            from: nil
        )
        if !didOpen {
            NSApplication.shared.sendAction(
                Selector(("showPreferencesWindow:")),
                to: nil,
                from: nil
            )
        }
    }

    private func panelCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct MetricView: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

private struct ClientUsageView: View {
    let client: ClientUsageGroup

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text(client.id)
                    .font(.subheadline.weight(.semibold))
                Text(DisplayFormatters.percentage(client.percentage))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                valuePair(tokens: client.tokens, cost: client.cost, emphasized: true)
            }
            .padding(10)

            if !client.models.isEmpty {
                ForEach(client.models) { model in
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Circle()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 4, height: 4)
                        Text(model.id)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        valuePair(tokens: model.tokens, cost: model.cost, emphasized: false)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                }
            }
        }
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }

    private func valuePair(tokens: Double, cost: Double, emphasized: Bool) -> some View {
        VStack(alignment: .trailing, spacing: 1) {
            Text(DisplayFormatters.compactNumber(tokens))
                .font(emphasized ? .caption.weight(.semibold) : .caption.monospacedDigit())
            Text(DisplayFormatters.currency(cost))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

private struct ErrorStateView: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Button("处理") { action() }
                .font(.caption)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct StatusBanner: View {
    let text: String
    let color: Color
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView().controlSize(.small) }
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).lineLimit(3)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

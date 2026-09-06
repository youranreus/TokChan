import SwiftUI

struct DashboardView: View {
    @ObservedObject var viewModel: DashboardViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                if let profile = viewModel.identityProfile {
                    header(profile)
                } else {
                    HStack {
                        Text("TokChan").font(.headline)
                        Spacer()
                        refreshButton
                    }
                }
                operationBanner
                Picker("时间范围", selection: Binding(
                    get: { viewModel.selectedPeriod },
                    set: { period in Task { await viewModel.selectPeriod(period) } }
                )) {
                    ForEach(ProfilePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .accessibilityIdentifier("period-picker")

                if let profile = viewModel.profileState.loadedValue {
                    metrics(profile)
                    TokenBreakdownView(breakdown: profile.breakdown)
                    HStack {
                        Text("客户端用量").font(.caption.weight(.semibold))
                        Spacer()
                        Text(profile.dateRange?.displayText ?? "暂无日期范围")
                            .font(.system(size: 10)).monospacedDigit()
                    }
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("usage-heading")
                }
            }
            .padding(14)
            .fixedSize(horizontal: false, vertical: true)

            usageContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 380, height: 680)
        .background(.background)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("dashboard-panel")
        #if DEBUG
        .accessibilityValue("\(viewModel.panelAppearanceCount):\(viewModel.panelDisappearanceCount)")
        #endif
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
                Text("@\(profile.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if let freshnessText {
                    Text(freshnessText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .help(freshnessText)
                        .accessibilityIdentifier("snapshot-updated-at")
                }
            }

            Spacer(minLength: 8)

            refreshButton
        }
    }

    private var refreshButton: some View {
        Button {
            Task { await viewModel.refresh() }
        } label: {
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .frame(width: 20, height: 20)
        .buttonStyle(.borderless)
        .disabled(viewModel.isLoading)
        .help("提交本地用量并刷新全部范围")
        .accessibilityLabel("提交并刷新")
        .accessibilityIdentifier("submit-refresh-button")
    }

    private func metrics(_ profile: DashboardData) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            MetricView(title: "Tokens", value: DisplayFormatters.compactNumber(profile.totalTokens))
            MetricView(title: "成本", value: DisplayFormatters.currency(profile.totalCost))
            MetricView(title: "排名", value: profile.rank.map { "#\($0)" } ?? "—")
            MetricView(title: "活跃天数", value: "\(profile.activeDays)")
        }
    }

    @ViewBuilder
    private var operationBanner: some View {
        switch viewModel.dashboardOperation {
        case .idle:
            EmptyView()
        case .submitting, .pushing, .pulling, .runningAutosubmit, .savingSettings:
            EmptyView()
        case let .succeeded(message):
            StatusBanner(text: message, color: .green, showsProgress: false)
        case let .failed(message):
            StatusBanner(text: message, color: .red, showsProgress: false)
        }
    }

    @ViewBuilder
    private var usageContent: some View {
        switch viewModel.profileState {
        case .idle, .loading:
            Color.clear
        case let .failed(message):
            ErrorStateView(title: "资料暂不可用", message: message) {
                Task { await viewModel.retryStatistics() }
            }
            .padding(.horizontal, 14)
        case let .loaded(profile):
            if profile.clients.isEmpty {
                Text("此范围暂时没有已提交的客户端或模型明细。")
                    .font(.callout).foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(profile.clients) { client in
                            ClientUsageView(client: client)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 14)
                }
                .id(profile.period)
                .accessibilityIdentifier("client-usage-scroll")
            }
        }
    }

    private var freshnessText: String? {
        SnapshotFreshnessFormatter.text(
            fetchedAt: viewModel.cacheSavedAt,
            dataDate: viewModel.profileState.loadedValue?.dateRange?.end
        )
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
    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center) {
                ClientIcon(clientID: client.id)
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
                ForEach(isExpanded ? client.models : Array(client.models.prefix(5))) { model in
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
                    .accessibilityIdentifier("model-\(client.id)-\(model.id)")
                }
                if client.models.count > 5 {
                    Button(isExpanded ? "收起" : "展开全部（\(client.models.count) 个模型）") {
                        isExpanded.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .accessibilityIdentifier("expand-models-\(client.id)")
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

struct StatusBanner: View {
    let text: String
    let color: Color
    let showsProgress: Bool

    var body: some View {
        HStack(spacing: 8) {
            if showsProgress { ProgressView().controlSize(.small) }
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).font(.caption).lineLimit(2).help(text)
            Spacer()
        }
        .padding(8)
        .background(color.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
    }
}

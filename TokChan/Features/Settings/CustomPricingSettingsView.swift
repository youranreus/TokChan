import SwiftUI

struct CustomPricingSettingsView: View {
    @ObservedObject var viewModel: CustomPricingViewModel
    @State private var confirmsDeletion = false
    @State private var showsDiagnosticDetails = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            fileContent
            Divider()
            diagnosticSection
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: editorPresented) {
            CustomPricingEditorView(viewModel: viewModel)
        }
        .alert("删除价格条目？", isPresented: $confirmsDeletion) {
            Button("取消", role: .cancel) {}
            Button("删除", role: .destructive) { viewModel.deleteSelected() }
        } message: {
            Text("将从 custom-pricing.json 删除 \(viewModel.selectedModelID ?? "所选条目")。此操作不会提交用量。")
        }
        .task {
            // The view model lives for the app lifetime, so reopening Settings
            // must refresh bytes that an external editor may have changed.
            await viewModel.load()
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("自定义价格")
                .font(.title3.weight(.semibold))
            Text("价格单位均为美元 / 1M Tokens。空值表示未填写，$0 表示明确免费。")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let url = viewModel.snapshot?.fileURL {
                Text(url.path)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                    .help(url.path)
            }
        }
    }

    @ViewBuilder
    private var fileContent: some View {
        switch viewModel.fileState {
        case .idle, .loading:
            HStack { Spacer(); ProgressView("正在读取价格文件…"); Spacer() }
                .frame(minHeight: 250)
        case let .failed(message):
            VStack(spacing: 10) {
                Label("无法读取价格文件", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text(message).foregroundStyle(.secondary).textSelection(.enabled)
                Button("重试") { Task { await viewModel.reload() } }
            }
            .frame(maxWidth: .infinity, minHeight: 250)
        case let .loaded(snapshot):
            pricingList(snapshot)
        }
    }

    private func pricingList(_ snapshot: CustomPricingSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if snapshot.entries.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "dollarsign.circle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(snapshot.exists ? "价格文件中还没有条目" : "价格文件尚未创建")
                        .font(.headline)
                    Text("添加第一条价格后将创建最小合法文件。")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("添加价格…") { viewModel.beginAdd() }
                        .disabled(!viewModel.canModify)
                }
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                Table(snapshot.entries, selection: $viewModel.selectedModelID) {
                    TableColumn("模型") { entry in
                        HStack(spacing: 5) {
                            Text(entry.modelID).lineLimit(1).help(entry.modelID)
                            if let issue = entry.issue {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .help(issue)
                                    .accessibilityLabel(issue)
                            }
                        }
                    }
                    .width(min: 220, ideal: 300)
                    TableColumn("输入") { Text(price(entry: $0.inputPrice)) }
                        .width(min: 78, ideal: 96)
                    TableColumn("输出") { Text(price(entry: $0.outputPrice)) }
                        .width(min: 78, ideal: 96)
                    TableColumn("缓存读") { Text(price(entry: $0.cacheReadPrice)) }
                        .width(min: 78, ideal: 96)
                    TableColumn("缓存写") { Text(price(entry: $0.cacheWritePrice)) }
                        .width(min: 78, ideal: 96)
                }
                .frame(minHeight: 220)
                .accessibilityIdentifier("custom-pricing-table")
            }

            selectedDetails
            HStack {
                Button { viewModel.beginAdd() } label: { Label("添加", systemImage: "plus") }
                    .disabled(!viewModel.canModify)
                    .accessibilityIdentifier("custom-pricing-add")
                Button { if let entry = viewModel.selectedEntry { viewModel.beginEdit(entry) } } label: {
                    Label("编辑", systemImage: "pencil")
                }
                .disabled(viewModel.selectedEntry == nil || !viewModel.canModify)
                Button { confirmsDeletion = true } label: { Label("删除", systemImage: "trash") }
                    .disabled(viewModel.selectedEntry == nil || !viewModel.canModify)
                Spacer()
                Button { Task { await viewModel.reload() } } label: {
                    Label("重新载入", systemImage: "arrow.clockwise")
                }
                .disabled(viewModel.operation.isBusy)
            }
        }
    }

    @ViewBuilder
    private var selectedDetails: some View {
        if let entry = viewModel.selectedEntry {
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.modelID).font(.caption.monospaced()).textSelection(.enabled)
                HStack(alignment: .top) {
                    Text("来源：\(entry.source ?? "未填写")")
                    Divider().frame(height: 14)
                    Text("备注：\(entry.notes ?? "未填写")")
                        .lineLimit(2).help(entry.notes ?? "未填写")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                if let issue = entry.issue {
                    Text(issue).font(.caption).foregroundStyle(.orange).textSelection(.enabled)
                }
            }
        } else {
            Text("选择条目可查看完整模型 ID、来源和备注。")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var diagnosticSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("缺失价格检查").font(.headline)
                    Text("使用已保存的 npx 与 Tokscale 版本，按 submit 默认范围执行 --dry-run；不会提交用量。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if case .checking = viewModel.operation { ProgressView().controlSize(.small) }
                Button("检查缺失价格") { Task { await viewModel.checkMissingPricing() } }
                    .disabled(viewModel.snapshot == nil || viewModel.operation.isBusy)
                    .accessibilityIdentifier("custom-pricing-check")
            }

            operationFeedback
            if let report = viewModel.report { diagnosticReport(report) }
        }
    }

    @ViewBuilder
    private var operationFeedback: some View {
        switch viewModel.operation {
        case .idle:
            EmptyView()
        case .loading:
            Label("正在读取价格文件…", systemImage: "arrow.clockwise")
                .font(.caption).foregroundStyle(.secondary)
        case .saving:
            Label("正在保存价格文件…", systemImage: "arrow.clockwise")
                .font(.caption).foregroundStyle(.secondary)
        case .checking:
            Text("正在扫描默认提交范围；Tokscale 可能会同步部分本地数据源。")
                .font(.caption).foregroundStyle(.secondary)
        case let .succeeded(message):
            Text(message).font(.caption).foregroundStyle(.green)
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.red).textSelection(.enabled).help(message)
        }
    }

    private func diagnosticReport(_ report: PricingDiagnosticReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if viewModel.isReportStale {
                Label("价格文件或 CLI 配置已变化，此报告待重新检查。", systemImage: "clock.badge.exclamationmark")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                reportSummary(report)
                Spacer()
                Text(report.checkedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption).foregroundStyle(.secondary)
            }
            if !report.items.isEmpty {
                List(report.items) { item in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.modelID ?? item.providerModel)
                                .font(.body.monospaced()).textSelection(.enabled)
                            Text("提供方：\(item.provider ?? "无法确定") · 原始标识：\(item.providerModel)")
                                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                            Text(item.reason).font(.caption).foregroundStyle(.secondary)
                            Text(impact(item)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(viewModel.hasMatchingCoverage(for: item) ? "编辑覆盖" : "补价…") {
                            viewModel.beginFixing(item)
                        }
                        .disabled(viewModel.isReportStale || item.modelID == nil || viewModel.operation.isBusy)
                    }
                }
                .frame(minHeight: 90, maxHeight: 150)
            }
            ForEach(report.warnings, id: \.self) { warning in
                Text(warning).font(.caption).foregroundStyle(.orange).lineLimit(2).help(warning)
            }
            DisclosureGroup("原始诊断详情", isExpanded: $showsDiagnosticDetails) {
                ScrollView {
                    Text(report.details.isEmpty ? "Tokscale 未提供详情。" : report.details)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }
            .font(.caption)
        }
    }

    @ViewBuilder
    private func reportSummary(_ report: PricingDiagnosticReport) -> some View {
        switch report.outcome {
        case .missingPricing:
            Label("发现 \(report.items.count) 个缺价模型", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .noMissingPricing:
            Label("本次默认范围未发现缺失价格", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .noData:
            Label("默认范围内没有可检查的用量", systemImage: "info.circle")
                .foregroundStyle(.secondary)
        case .partialData:
            Label("部分数据源检查失败，无法确认价格完整", systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .unknownFormat:
            Label("无法判断检查结果，请查看原始详情", systemImage: "questionmark.circle.fill")
                .foregroundStyle(.orange)
        }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { viewModel.isEditorPresented },
            set: { if !$0 { viewModel.cancelEditing() } }
        )
    }

    private func price(entry value: Double?) -> String {
        guard let value else { return "—" }
        return "$" + value.formatted(
            .number.precision(.fractionLength(0...8)).locale(Locale(identifier: "en_US_POSIX"))
        )
    }

    private func impact(_ item: MissingPricingItem) -> String {
        let messages = item.messageCount.map { "\($0) 条消息" } ?? "消息数未知"
        let tokens = item.tokenCount.map {
            $0.formatted(.number.precision(.fractionLength(0...2))) + " Tokens"
        } ?? "Tokens 未知"
        return "\(messages) · \(tokens)"
    }
}

private struct CustomPricingEditorView: View {
    @ObservedObject var viewModel: CustomPricingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.title2.weight(.semibold))
            Form {
                TextField("模型 ID", text: $viewModel.draft.modelID)
                    .textFieldStyle(.roundedBorder)
                Section("价格（美元 / 1M Tokens）") {
                    priceField("输入", text: $viewModel.draft.inputPrice)
                    priceField("输出", text: $viewModel.draft.outputPrice)
                    priceField("缓存读取", text: $viewModel.draft.cacheReadPrice)
                    priceField("缓存写入", text: $viewModel.draft.cacheWritePrice)
                    Text("留空表示没有该价格；输入 0 表示明确免费。不会自动推测或补齐。")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Section("元数据") {
                    TextField("来源（可选）", text: $viewModel.draft.source)
                    TextField("备注（可选）", text: $viewModel.draft.notes, axis: .vertical)
                        .lineLimit(2...4)
                }
            }
            .formStyle(.grouped)

            if let error = viewModel.editorError {
                Text(error).font(.caption).foregroundStyle(.red).textSelection(.enabled)
            }
            HStack {
                Spacer()
                Button("取消") { viewModel.cancelEditing() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") { viewModel.saveDraft() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(viewModel.operation.isBusy)
            }
        }
        .padding(20)
        .frame(width: 520, height: 540)
    }

    private var title: String {
        if case .edit = viewModel.editorMode { return "编辑自定义价格" }
        return "添加自定义价格"
    }

    private func priceField(_ label: String, text: Binding<String>) -> some View {
        HStack {
            TextField(label, text: text)
            Text("USD / 1M").font(.caption).foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
struct CustomPricingSettingsView_Previews: PreviewProvider {
    @MainActor
    static var previews: some View {
        CustomPricingSettingsView(
            viewModel: CustomPricingViewModel(
                cli: PreviewCLIService(),
                store: PreviewCustomPricingStore(),
                preferencesStore: PreviewPreferencesStore(),
                npxLocator: PreviewNpxLocator()
            )
        )
        .frame(width: 900, height: 680)
    }
}
#endif

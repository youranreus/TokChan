import AppKit
import SwiftUI

struct AboutCopy {
    static let summary = "Tokscale的状态栏预览应用"
    static let bylinePrefix = "Made with love by "
    static let author = "季悠然"
    static let authorURL = URL(string: "https://blog.mitsuha.space")!
}

struct AutosubmitSettingsDraft: Equatable {
    var enabled: Bool
    var intervalMinutes: Int
    var clientsText: String
    var filterKind: AutosubmitFilterKind
    var year: String
    var since: String
    var until: String
    private(set) var isDirty: Bool

    init(status: AutosubmitStatus?) {
        let configuration = status.map(AutosubmitConfiguration.init) ?? AutosubmitConfiguration(
            enabled: false,
            intervalMinutes: 1_440,
            clients: [],
            filterKind: .all,
            year: "",
            since: "",
            until: ""
        )
        enabled = configuration.enabled
        intervalMinutes = configuration.intervalMinutes
        clientsText = configuration.clients.joined(separator: ", ")
        filterKind = configuration.filterKind
        year = configuration.year
        since = configuration.since
        until = configuration.until
        isDirty = false
    }

    var configuration: AutosubmitConfiguration {
        AutosubmitConfiguration(
            enabled: enabled,
            intervalMinutes: intervalMinutes,
            clients: clientsText.split(separator: ",").map(String.init),
            filterKind: filterKind,
            year: year,
            since: since,
            until: until
        )
    }

    mutating func edit<Value>(_ keyPath: WritableKeyPath<Self, Value>, to value: Value) {
        self[keyPath: keyPath] = value
        isDirty = true
    }

    mutating func synchronize(with status: AutosubmitStatus) {
        guard !isDirty else { return }
        self = Self(status: status)
    }

    mutating func confirm(with status: AutosubmitStatus) {
        self = Self(status: status)
    }
}

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var launchAtLoginModel: LaunchAtLoginSettingsModel
    @ObservedObject var customPricingViewModel: CustomPricingViewModel
    @Environment(\.scenePhase) private var scenePhase

    private enum SettingsTab: Hashable {
        case general
        case autosubmit
        case customPricing
        case about
    }

    @State private var isNpxOverrideExpanded: Bool
    @State private var autosubmitDraft: AutosubmitSettingsDraft
    @State private var selectedTab: SettingsTab = .general

    init(
        viewModel: DashboardViewModel,
        launchAtLoginModel: LaunchAtLoginSettingsModel,
        customPricingViewModel: CustomPricingViewModel
    ) {
        self.viewModel = viewModel
        self.launchAtLoginModel = launchAtLoginModel
        self.customPricingViewModel = customPricingViewModel
        _isNpxOverrideExpanded = State(
            initialValue: viewModel.npxPathStatus(for: viewModel.preferences.npxPath).shouldExpandOverride
        )
        _autosubmitDraft = State(
            initialValue: AutosubmitSettingsDraft(status: viewModel.currentAutosubmitStatus)
        )
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            settingsPage {
                generalSettings
            }
            .tabItem {
                Label("常规", systemImage: "slider.horizontal.3")
            }
            .tag(SettingsTab.general)

            autosubmitPage
            .tabItem {
                Label("自动提交", systemImage: "arrow.clockwise.circle")
            }
            .tag(SettingsTab.autosubmit)

            CustomPricingSettingsView(viewModel: customPricingViewModel)
                .tabItem {
                    Label("自定义价格", systemImage: "dollarsign.circle")
                }
                .tag(SettingsTab.customPricing)

            settingsPage {
                aboutSettings
            }
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .frame(
            minWidth: 760, idealWidth: 900, maxWidth: 1_100,
            minHeight: 620, idealHeight: 680, maxHeight: 900
        )
        .navigationTitle("TokChan! 设置")
        .task {
            launchAtLoginModel.refresh()
            await viewModel.load()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active {
                launchAtLoginModel.refresh()
            }
        }
        .onChange(of: viewModel.currentAutosubmitStatus) { status in
            if let status {
                autosubmitDraft.synchronize(with: status)
            }
        }
    }

    private func settingsPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var autosubmitPage: some View {
        VStack(spacing: 0) {
            autosubmitSettings
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .accessibilityIdentifier("settings-autosubmit-page")

            HStack {
                operationFeedback
                Spacer()
                Button("应用自动提交设置") {
                    Task {
                        let applied = await viewModel.applyAutosubmit(autosubmitDraft.configuration)
                        if applied, let status = viewModel.currentAutosubmitStatus {
                            autosubmitDraft.confirm(with: status)
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.operation.isRunning)
                .accessibilityIdentifier("apply-autosubmit-settings")
            }
            .padding()
            .background(Color.secondary.opacity(0.06))
        }
    }

    @ViewBuilder
    private var operationFeedback: some View {
        switch viewModel.operation {
        case .idle:
            EmptyView()
        case .applyingAutosubmit:
            ProgressView().controlSize(.small)
            Text("正在应用自动提交设置…").font(.caption)
        case .submitting, .pushing, .pulling, .runningAutosubmit:
            ProgressView().controlSize(.small)
            Text("正在运行…").font(.caption)
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2).help(message)
        case let .succeeded(message):
            Text(message).font(.caption).foregroundStyle(.green).lineLimit(2)
                .accessibilityIdentifier("settings-operation-success")
        }
    }

    private var generalSettings: some View {
        Form {
            Section("基本配置") {
                TextField("Tokscale 用户名", text: preferenceBinding(\UserPreferences.username))
                TextField("Tokscale 版本", text: preferenceBinding(\UserPreferences.tokscaleVersion))
                    .help("填写 latest 或 4.15.0 这样的完整版本号")
            }
            .disabled(viewModel.operation.isRunning)

            Section("状态栏文案") {
                Toggle("显示用量摘要", isOn: preferenceBinding(\UserPreferences.statusTextEnabled))
                    .accessibilityIdentifier("status-text-enabled")

                TextField("文案模板", text: preferenceBinding(\UserPreferences.statusTextTemplate))
                    .disabled(!viewModel.preferences.statusTextEnabled)
                    .accessibilityIdentifier("status-text-template")

                Picker("统计范围", selection: preferenceBinding(\UserPreferences.statusTextPeriod)) {
                    ForEach(ProfilePeriod.allCases) { period in
                        Text(period.title).tag(period)
                    }
                }
                .disabled(!viewModel.preferences.statusTextEnabled)
                .accessibilityIdentifier("status-text-period")

                Text("支持的模板变量：{token}、{cost}")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            launchAtLoginSettings

            Section("npx") {
                npxStatusView(npxPathStatus)

                Button(isNpxOverrideExpanded ? "收起自定义设置" : "使用自定义 npx…") {
                    isNpxOverrideExpanded.toggle()
                }
                .accessibilityIdentifier("npx-override-disclosure")

                if isNpxOverrideExpanded {
                    npxOverrideControls
                }
            }
            .disabled(viewModel.operation.isRunning)
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("settings-general-page")
    }

    private var launchAtLoginSettings: some View {
        Section("启动") {
            Toggle("登录时启动 TokChan", isOn: launchAtLoginBinding)
                .disabled(launchAtLoginModel.isUpdating)
                .accessibilityIdentifier("launch-at-login-toggle")

            if launchAtLoginModel.isUpdating {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在更新登录项…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            launchAtLoginStatus

            if let errorMessage = launchAtLoginModel.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(errorMessage)
                    .accessibilityIdentifier("launch-at-login-error")
            }
        }
    }

    private var launchAtLoginBinding: Binding<Bool> {
        Binding(
            get: { launchAtLoginModel.isEnabled },
            set: { launchAtLoginModel.setEnabled($0) }
        )
    }

    @ViewBuilder
    private var launchAtLoginStatus: some View {
        switch launchAtLoginModel.status {
        case .enabled, .notRegistered, .notFound:
            EmptyView()
        case .requiresApproval:
            VStack(alignment: .leading, spacing: 8) {
                Label(
                    "已添加登录项，但仍需在系统设置中批准后才会自动启动。",
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(.orange)

                Button("打开系统设置") {
                    launchAtLoginModel.openSystemSettingsLoginItems()
                }
                .accessibilityIdentifier("open-login-items-settings")
            }
        }
    }

    private func npxStatusView(_ status: NpxPathStatus) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: npxStatusIcon(for: status))
                .foregroundStyle(npxStatusColor(for: status))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(npxStatusTitle(for: status))
                    .font(.body.weight(.medium))
                if let path = npxResolvedPath(for: status) {
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                } else {
                    Text("未找到可执行的 npx。请安装 Node.js，或在下方选择自定义文件。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("npx-detection-status")
    }

    private var npxOverrideControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                TextField(
                    "自定义 npx 路径",
                    text: preferenceBinding(\UserPreferences.npxPath)
                )
                .accessibilityIdentifier("npx-override-path")
                Button("选择…") { chooseNpx() }
            }

            HStack {
                Text("自定义路径必须是绝对路径且文件可执行。留空会恢复自动探测。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !viewModel.preferences.npxPath.isEmpty {
                    Button("清除覆盖") { clearNpxOverride() }
                        .accessibilityIdentifier("npx-clear-override")
                }
            }
        }
    }

    private var npxPathStatus: NpxPathStatus {
        viewModel.npxPathStatus(for: viewModel.preferences.npxPath)
    }

    private func npxStatusTitle(for status: NpxPathStatus) -> String {
        switch status {
        case .automatic:
            return "已自动探测 npx"
        case .custom:
            return "正在使用自定义 npx"
        case .automaticFallback:
            return "自定义路径不可用，已自动回退"
        case .unavailable:
            return "未探测到 npx"
        }
    }

    private func npxResolvedPath(for status: NpxPathStatus) -> String? {
        switch status {
        case let .automatic(url), let .custom(url), let .automaticFallback(url):
            return url.path
        case .unavailable:
            return nil
        }
    }

    private func npxStatusIcon(for status: NpxPathStatus) -> String {
        switch status {
        case .automatic, .custom:
            return "checkmark.circle.fill"
        case .automaticFallback:
            return "exclamationmark.triangle.fill"
        case .unavailable:
            return "xmark.circle.fill"
        }
    }

    private func npxStatusColor(for status: NpxPathStatus) -> Color {
        switch status {
        case .automatic, .custom:
            return .green
        case .automaticFallback:
            return .orange
        case .unavailable:
            return .red
        }
    }

    private var autosubmitSettings: some View {
        Form {
            Section("运行状态") {
                AutosubmitStatusView(viewModel: viewModel)
                if let error = viewModel.autosubmitLoadErrorMessage,
                   viewModel.currentAutosubmitStatus != nil {
                    Text("状态更新失败：\(error)")
                        .font(.caption).foregroundStyle(.orange)
                }
            }
            Section("自动提交") {
                Toggle("启用", isOn: autosubmitBinding(\AutosubmitSettingsDraft.enabled))

                HStack {
                    Text("间隔")
                    Spacer()
                    TextField(
                        "分钟",
                        value: autosubmitBinding(\AutosubmitSettingsDraft.intervalMinutes),
                        format: .number
                    )
                    .frame(width: 72)
                    Text("分钟").foregroundStyle(.secondary)
                }
                .disabled(!autosubmitDraft.enabled)

                TextField(
                    "客户端（逗号分隔，留空表示全部）",
                    text: autosubmitBinding(\AutosubmitSettingsDraft.clientsText)
                )
                .disabled(!autosubmitDraft.enabled)

                Picker(
                    "提交范围",
                    selection: autosubmitBinding(\AutosubmitSettingsDraft.filterKind)
                ) {
                    ForEach(AutosubmitFilterKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .disabled(!autosubmitDraft.enabled)

                filterFields
            }
        }
        .formStyle(.grouped)
    }

    private var aboutSettings: some View {
        VStack(spacing: 14) {
            Image("AboutLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 112, height: 104)
                .accessibilityLabel("TokChan Logo")

            Text("TokChan!")
                .font(.title2.weight(.semibold))

            Text("版本 \(appVersion)")
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text(AboutCopy.summary)
                HStack(spacing: 0) {
                    Text(AboutCopy.bylinePrefix)
                    Link(AboutCopy.author, destination: AboutCopy.authorURL)
                        .accessibilityIdentifier("about-author-link")
                }
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
        .accessibilityIdentifier("settings-about-page")
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    @ViewBuilder
    private var filterFields: some View {
        switch autosubmitDraft.filterKind {
        case .year:
            TextField(
                "年份（YYYY）",
                text: autosubmitBinding(\AutosubmitSettingsDraft.year)
            )
            .disabled(!autosubmitDraft.enabled)
        case .range:
            HStack {
                TextField(
                    "开始日期（YYYY-MM-DD）",
                    text: autosubmitBinding(\AutosubmitSettingsDraft.since)
                )
                TextField(
                    "结束日期（YYYY-MM-DD）",
                    text: autosubmitBinding(\AutosubmitSettingsDraft.until)
                )
            }
            .disabled(!autosubmitDraft.enabled)
        default:
            EmptyView()
        }
    }

    private func preferenceBinding<Value>(
        _ keyPath: WritableKeyPath<UserPreferences, Value>
    ) -> Binding<Value> {
        Binding(
            get: { viewModel.preferences[keyPath: keyPath] },
            set: { value in
                var updated = viewModel.preferences
                updated[keyPath: keyPath] = value
                viewModel.updatePreferences(updated)
            }
        )
    }

    private func autosubmitBinding<Value>(
        _ keyPath: WritableKeyPath<AutosubmitSettingsDraft, Value>
    ) -> Binding<Value> {
        Binding(
            get: { autosubmitDraft[keyPath: keyPath] },
            set: { autosubmitDraft.edit(keyPath, to: $0) }
        )
    }

    private func clearNpxOverride() {
        var updated = viewModel.preferences
        updated.npxPath = ""
        viewModel.updatePreferences(updated)
        if !viewModel.npxPathStatus(for: "").shouldExpandOverride {
            isNpxOverrideExpanded = false
        }
    }

    private func chooseNpx() {
        let panel = NSOpenPanel()
        panel.title = "选择 npx 可执行文件"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url {
            var updated = viewModel.preferences
            updated.npxPath = url.path
            viewModel.updatePreferences(updated)
        }
    }
}

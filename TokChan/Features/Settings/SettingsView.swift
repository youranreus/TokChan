import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @ObservedObject var launchAtLoginModel: LaunchAtLoginSettingsModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    private enum SettingsTab: Hashable {
        case general
        case autosubmit
        case about
    }

    @State private var username: String
    @State private var version: String
    @State private var npxPath: String
    @State private var isNpxOverrideExpanded: Bool
    @State private var autosubmitEnabled: Bool
    @State private var intervalMinutes: Int
    @State private var clientsText: String
    @State private var filterKind: AutosubmitFilterKind
    @State private var year: String
    @State private var since: String
    @State private var until: String
    @State private var selectedTab: SettingsTab = .general

    init(
        viewModel: DashboardViewModel,
        launchAtLoginModel: LaunchAtLoginSettingsModel
    ) {
        self.viewModel = viewModel
        self.launchAtLoginModel = launchAtLoginModel
        let preferences = viewModel.preferences
        let autosubmit = viewModel.currentAutosubmitStatus.map(AutosubmitConfiguration.init)
            ?? AutosubmitConfiguration(
                enabled: false,
                intervalMinutes: 1_440,
                clients: [],
                filterKind: .all,
                year: "",
                since: "",
                until: ""
            )

        _username = State(initialValue: preferences.username)
        _version = State(initialValue: preferences.tokscaleVersion)
        _npxPath = State(initialValue: preferences.npxPath)
        _isNpxOverrideExpanded = State(
            initialValue: viewModel.npxPathStatus(for: preferences.npxPath).shouldExpandOverride
        )
        _autosubmitEnabled = State(initialValue: autosubmit.enabled)
        _intervalMinutes = State(initialValue: autosubmit.intervalMinutes)
        _clientsText = State(initialValue: autosubmit.clients.joined(separator: ", "))
        _filterKind = State(initialValue: autosubmit.filterKind)
        _year = State(initialValue: autosubmit.year)
        _since = State(initialValue: autosubmit.since)
        _until = State(initialValue: autosubmit.until)
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

            settingsPage {
                autosubmitSettings
            }
            .tabItem {
                Label("自动提交", systemImage: "arrow.clockwise.circle")
            }
            .tag(SettingsTab.autosubmit)

            settingsPage {
                aboutSettings
            }
            .tabItem {
                Label("关于", systemImage: "info.circle")
            }
            .tag(SettingsTab.about)
        }
        .frame(width: 560, height: 600)
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
    }

    private func settingsPage<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            HStack {
                operationFeedback
                Spacer()
                Button("保存") {
                    Task {
                        let saved = await viewModel.saveSettings(
                            preferences: enteredPreferences,
                            autosubmit: enteredAutosubmit
                        )
                        if saved { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(viewModel.operation.isRunning)
            }
            .padding()
            .background(Color.secondary.opacity(0.06))
        }
    }

    @ViewBuilder
    private var operationFeedback: some View {
        switch viewModel.operation {
        case .idle: EmptyView()
        case .submitting, .runningAutosubmit, .savingSettings:
            ProgressView().controlSize(.small)
            Text(viewModel.operation == .savingSettings ? "正在保存…" : "正在运行…")
                .font(.caption)
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.red).lineLimit(2).help(message)
        case let .succeeded(message):
            Text(message).font(.caption).foregroundStyle(.green).lineLimit(2)
                .accessibilityIdentifier("settings-operation-success")
        }
    }

    private var generalSettings: some View {
        Form {
            Section("资料与命令行") {
                TextField("Tokscale 用户名", text: $username)
                TextField("Tokscale 版本", text: $version)
                    .help("填写 latest 或 4.15.0 这样的完整版本号")
            }

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

            launchAtLoginSettings
        }
        .formStyle(.grouped)
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
        case .enabled:
            Label("已启用，TokChan 将在登录后自动启动。", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.green)
        case .notRegistered:
            Text("未启用。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
        case .notFound:
            Text("系统尚未建立 TokChan 登录项记录。打开开关可尝试添加。")
                .font(.caption)
                .foregroundStyle(.secondary)
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
                TextField("自定义 npx 路径", text: $npxPath)
                    .accessibilityIdentifier("npx-override-path")
                Button("选择…") { chooseNpx() }
            }

            HStack {
                Text("自定义路径必须是绝对路径且文件可执行。留空会恢复自动探测。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if !npxPath.isEmpty {
                    Button("清除覆盖") { clearNpxOverride() }
                        .accessibilityIdentifier("npx-clear-override")
                }
            }
        }
    }

    private var npxPathStatus: NpxPathStatus {
        viewModel.npxPathStatus(for: npxPath)
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
                Toggle("启用", isOn: $autosubmitEnabled)

                HStack {
                    Text("间隔")
                    Spacer()
                    TextField("分钟", value: $intervalMinutes, format: .number)
                        .frame(width: 72)
                    Text("分钟").foregroundStyle(.secondary)
                }
                .disabled(!autosubmitEnabled)

                TextField("客户端（逗号分隔，留空表示全部）", text: $clientsText)
                    .disabled(!autosubmitEnabled)

                Picker("提交范围", selection: $filterKind) {
                    ForEach(AutosubmitFilterKind.allCases) { kind in
                        Text(kind.title).tag(kind)
                    }
                }
                .disabled(!autosubmitEnabled)

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

            Text("TokChan 是 Tokscale 的 macOS 菜单栏伴侣，用于查看用量并管理自动提交。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "未知"
    }

    @ViewBuilder
    private var filterFields: some View {
        switch filterKind {
        case .year:
            TextField("年份（YYYY）", text: $year)
                .disabled(!autosubmitEnabled)
        case .range:
            HStack {
                TextField("开始日期（YYYY-MM-DD）", text: $since)
                TextField("结束日期（YYYY-MM-DD）", text: $until)
            }
            .disabled(!autosubmitEnabled)
        default:
            EmptyView()
        }
    }

    private var enteredPreferences: UserPreferences {
        UserPreferences(username: username, tokscaleVersion: version, npxPath: npxPath)
    }

    private var enteredAutosubmit: AutosubmitConfiguration {
        AutosubmitConfiguration(
            enabled: autosubmitEnabled,
            intervalMinutes: intervalMinutes,
            clients: clientsText.split(separator: ",").map(String.init),
            filterKind: filterKind,
            year: year,
            since: since,
            until: until
        )
    }

    private func clearNpxOverride() {
        npxPath = ""
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
            npxPath = url.path
        }
    }
}

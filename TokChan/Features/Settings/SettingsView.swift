import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

    private enum SettingsTab: Hashable {
        case general
        case autosubmit
        case about
    }

    @State private var username: String
    @State private var version: String
    @State private var npxPath: String
    @State private var autosubmitEnabled: Bool
    @State private var intervalMinutes: Int
    @State private var clientsText: String
    @State private var filterKind: AutosubmitFilterKind
    @State private var year: String
    @State private var since: String
    @State private var until: String
    @State private var selectedTab: SettingsTab = .general

    init(viewModel: DashboardViewModel) {
        self.viewModel = viewModel
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
        .task { await viewModel.load() }
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

                HStack {
                    TextField("npx 可执行文件", text: $npxPath)
                    Button("选择…") { chooseNpx() }
                }
            }
        }
        .formStyle(.grouped)
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

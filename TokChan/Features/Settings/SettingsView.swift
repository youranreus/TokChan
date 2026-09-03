import AppKit
import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: DashboardViewModel
    @Environment(\.dismiss) private var dismiss

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
        VStack(spacing: 0) {
            HStack {
                Text("TokChan 设置")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("关闭设置")
            }
            .padding()

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

            HStack {
                if case let .failed(message) = viewModel.operation {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
                Spacer()
                Button("取消") { dismiss() }
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
        .frame(width: 500, height: 570)
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

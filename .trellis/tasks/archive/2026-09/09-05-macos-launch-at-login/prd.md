# 添加 macOS 开机自启动设置

## Goal

让用户能在 TokChan 的设置中控制应用是否随 macOS 用户登录自动启动，并让界面始终反映系统登录项的真实状态，而不是维护一份可能失真的应用内副本。

## Background

- TokChan 是最低支持 macOS 13 的 SwiftUI 菜单栏应用，入口使用 `MenuBarExtra` 和原生 `Settings` scene（`TokChan/TokChanApp.swift`）。
- 当前设置页已有「常规」「自动提交」「关于」三个原生偏好设置 Tab；「常规」页承载应用级常规配置（`TokChan/Features/Settings/SettingsView.swift`）。
- macOS 13 起，Apple 为主应用登录项提供 `ServiceManagement.SMAppService.mainApp`；其注册状态由系统拥有，并会出现在“系统设置 > 通用 > 登录项”中。

## Requirements

- 在设置的「常规」页提供“登录时启动 TokChan”开关；切换后立即向系统注册或注销，不依赖页面底部的“保存”按钮。
- 使用 macOS 13+ 的 `SMAppService.mainApp` 注册或注销主应用登录项，不使用弃用的 `SMLoginItemSetEnabled`，也不自行写入 LaunchAgent plist。
- 开关及辅助状态必须以 `SMAppService.status` 为事实来源，不在 `UserDefaults` 中重复保存启用状态。
- 注册、注销失败时恢复/刷新为系统真实状态，并向用户展示可理解的错误信息。
- 当系统返回 `requiresApproval` 时，设置页明确提示用户仍需在系统设置中批准，并提供打开“登录项”系统设置的操作。
- 用户从系统设置返回应用或重新打开设置页时，界面刷新登录项状态，以反映应用外部发生的变更。
- 保持现有 macOS 13 部署目标、SwiftUI Settings 架构和其他设置保存行为不变。
- 为 ServiceManagement 边界提供可注入、可单元测试的抽象；测试不应真实修改开发机登录项。

## Acceptance Criteria

- [ ] 用户可在「常规」设置中找到“登录时启动 TokChan”开关；切换后无需点击“保存”即可立即触发系统注册或注销。
- [ ] 启用后，TokChan 通过 `SMAppService.mainApp.register()` 注册，并在系统“登录项”列表中可见；注销后系统不再于登录时启动它。
- [ ] 设置页首次显示、重新激活或再次打开时，开关与系统当前注册状态一致。
- [ ] `enabled`、`notRegistered`、`requiresApproval`、`notFound` 四种系统状态都有明确且不会误导的 UI 映射。
- [ ] `requiresApproval` 状态提示用户前往系统设置，并能直接打开登录项面板。
- [ ] 注册或注销抛错时，设置页显示错误且不会错误地保留乐观状态。
- [ ] 单元测试覆盖状态映射、注册成功/失败、注销成功/失败和待批准状态，且不会操作真实系统登录项。
- [ ] `xcodebuild test -scheme TokChan -destination 'platform=macOS'` 通过。

## Out of Scope

- 支持 macOS 12 或更早系统。
- 创建独立 helper app、LaunchAgent 或 LaunchDaemon。
- “静默启动/登录后隐藏主窗口”选项；TokChan 本身是菜单栏应用，无普通主窗口启动流程。
- 自动绕过、模拟或修改用户在系统设置中的批准操作。
- 改造现有账号、npx 或自动提交设置的数据格式。


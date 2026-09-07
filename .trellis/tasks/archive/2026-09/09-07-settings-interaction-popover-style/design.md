# 设置生效模型与浮窗材质设计

## Baseline and Scope

实现分支直接从 `master` 创建并以 `master` 为 PR 目标。分支建立后先纳入 `feat/status-text-and-actions` 已完成的功能提交，使状态栏文案、即时推拉、相关测试与 spec 成为当前任务基线，再实施本次细化。保留现有 SwiftUI `Settings` scene、顶部原生 `TabView` preferences toolbar、应用级唯一 `DashboardViewModel`、`NSStatusItemCoordinator` 与 `.transient` `NSPopover`。

本次只调整两个既有模块的接口和呈现：

1. `DashboardViewModel` 将混合的全局保存拆为“本地偏好更新”和“自动提交配置应用”两个语义明确的入口。
2. `SettingsView` 让各 Tab 只展示自己拥有的操作；`DashboardView` 不再覆盖 AppKit popover 的系统背景。

## Settings Submission Model

### General preferences module

`DashboardViewModel` 提供一个小接口，接收完整的下一份 `UserPreferences`：

```swift
func updatePreferences(_ newPreferences: UserPreferences)
```

实现内部负责：

- 对 username、Tokscale version、npx path 做既有首尾空白规范化；状态栏模板字节保持原样。
- 比较规范化后的新旧用户名。真正跨账号时，先推进 profile generation / request identity，清除 `cachedProfiles`、`profileState` 中旧账号值、`identityProfile`、`cacheSavedAt`、`lastAutomaticAttempt` 和旧 profile error，再持久化不含旧账号 profiles 的快照。
- version 或 npx 改变时使已发出的 autosubmit status request 失效，避免旧 CLI context 的晚到响应覆盖新配置，但不清除与 CLI context 无关的 profile cache。
- 保存 `UserDefaults` 并发布 `preferences`。发布会复用 coordinator 现有订阅，从完整缓存立即重算状态栏文案。
- 不调用 submit、autosubmit configure/disable、profile fetch 或 status fetch。

`SettingsView` 不保留一份可能过期的整组 General 草稿。每个控件使用从 `viewModel.preferences` 读取、在 setter 中复制当前值并调用 `updatePreferences` 的 Binding。这样后到的身份发现不会被初始化时的旧快照覆盖，调用者也只需理解一个更新接口。npx 展开/收起仍是纯界面状态；文件选择与清除通过同一偏好入口立即持久化。

在任何显式 Dashboard/CLI operation 运行时，禁用会改变账号或 CLI context 的基本配置与 npx 控件，避免 operation 中途切换 context；状态栏文案开关、模板和范围仍可即时修改，因为它们只消费已发布缓存。

### Autosubmit configuration module

用异步入口替换原 `saveSettings(preferences:autosubmit:)`：

```swift
func applyAutosubmit(_ configuration: AutosubmitConfiguration) async -> Bool
```

调用顺序固定为：

1. 拒绝并发 operation，进入语义明确的 applying/saving-autosubmit operation 状态。
2. 从已经持久化的当前 preferences 解析 CLI context，并保留既有非空用户名校验。
3. 按开关执行一次 `configureAutosubmit` 或 `disableAutosubmit`。
4. 成功后只重读一次 autosubmit status；不使 profile batch 失效、不拉取统计、不 submit。
5. 发布成功/失败反馈并返回 Bool；无论结果如何都不关闭 Settings。

operation enum 的命名应反映“应用自动提交设置”，不再暗示所有设置正在保存。Dashboard 对该运行态继续不显示横幅；Settings 的自动提交 footer 显示小型进度或结果。

### Autosubmit draft synchronization

自动提交仍是显式确认编辑，因此保留 view-owned draft。增加 `isAutosubmitDirty`（或等价 baseline）并遵循：

- 初始化时优先采用已有 `currentAutosubmitStatus`，否则采用稳定默认值。
- `$autosubmitState` 首次或后续发布已加载状态时，只在 draft 尚未被用户编辑时回填。
- 任意用户编辑把 draft 标记为 dirty，后台状态不得覆盖。
- Apply 成功并完成 status reread 后，以确认后的状态回填 draft 并清除 dirty；失败保留用户草稿。

该规则防止窗口先以默认 disabled 构造、异步 status 后到时用户误把真实 enabled 配置关闭。

## Settings View Structure and Copy

`settingsPage` 不再拥有共享 footer，只负责让内容占满窗口，或直接由各 Tab 使用对应内容：

- General：无 footer，Section 顺序固定为“基本配置 → 状态栏文案 → 启动 → npx”。
- Autosubmit：保留自己的底部反馈栏和“应用自动提交设置”默认按钮。
- Custom Pricing：保持现有独立编辑/保存。
- About：无 footer。

状态栏模板说明固定为：

```text
支持的模板变量：{token}、{cost}
```

登录项呈现把状态映射收敛为：

- `.enabled`、`.notRegistered`、`.notFound`：无说明视图；Toggle 本身表达当前状态。
- `.requiresApproval`：保留系统批准警告与“打开系统设置”。
- updating：保留 ProgressView 与“正在更新登录项…”。
- error：保留错误信息。

## Popover Background Ownership

AppKit 已为 `NSPopover` 创建 popover visual-effect surface，并同时绘制箭头、圆角和阴影。当前 `DashboardView` 的根 `.background(.background)` 又在 380×680 内容 bounds 内绘制一层不透明 SwiftUI 背景，造成主体与箭头材质不同。

最小修复是删除根 `.background(.background)`，让无自绘背景的 `NSHostingController` 内容透出外层 AppKit popover surface。保留所有局部卡片背景；不添加 `.regularMaterial`、`NSVisualEffectView`、自绘箭头或 appearance hack，也不修改 coordinator 的 size、behavior、anchor 或生命周期。

## Data Flow and Invariants

- General 变化：View Binding → `updatePreferences` → UserDefaults + `@Published preferences` → status item title recompute；零外部请求。
- Username 变化：在发布新 preference 前失效旧 profile generation 并清除旧账号展示/缓存；下一次既有 panel load 或显式 pull 获取新数据。
- Autosubmit Apply：draft → `applyAutosubmit` → CLI configure/disable → status read → autosubmit state/cache；统计 profiles 与 `fetchedAt` 不变。
- Popover：AppKit `NSPopover` 是唯一根背景所有者；SwiftUI 只绘制内容和局部卡片。

必须保持完整 all/day/week/month profile batch、一账号约束、状态栏模板渲染、状态项左右键、自定义价格和登录项业务行为不变。

## Compatibility, Validation, and Rollback

- 保持 macOS 13，不引入依赖或持久化迁移。
- UserPreferences 的 key 与默认值不变；只改变写入时机。
- 自动化覆盖偏好零副作用、跨账号失效、autosubmit scoped apply、draft 同步和现有状态栏语义。
- 根背景连续性必须在真实 Aqua / Dark Aqua NSPopover 中人工确认；普通 borderless test window 不能验证箭头接缝。
- 若系统版本上透明 hosting root 不能正确透出 popover surface，可单独回滚该一行并重新评估 AppKit hosting 配置；不得先叠加第二层近似材质掩盖问题。
- 设置模型可通过恢复原 `saveSettings` 与 footer 回滚；UserDefaults schema 和远端状态无需迁移。
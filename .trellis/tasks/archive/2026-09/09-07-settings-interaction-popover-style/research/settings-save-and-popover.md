# 分层即时生效与 NSPopover 背景调研

## 调研范围

- 活跃任务由 `python3 ./.trellis/scripts/task.py current --source` 确认为 `.trellis/tasks/09-07-settings-interaction-popover-style`。
- 调研代码来源为 `feat/status-text-and-actions` 的 `3b69ca6164809bb1fadbc1ced7a94595fb5a03f8`，因为状态栏文案尚未进入 `master`；执行基线随后由用户改为从 `master` 创建任务分支并纳入该已完成提交序列。调研期间未切换分支、未修改产品文件。
- 下文将 **代码事实 / Apple 文档事实** 与 **实现建议（推断）** 分开标记。

## 结论摘要

1. 将 `DashboardViewModel.saveSettings(preferences:autosubmit:)` 拆成两个不同边界：
   - 同步、无 CLI/网络副作用的 General 偏好更新入口；每个控件变更立即写 `UserDefaults` 并发布 `preferences`。
   - 异步的 `applyAutosubmit(_:)`；只由“自动提交”Tab 内的显式“应用”按钮调用。
2. General 更新不得直接调用 `configureAutosubmit`、`disableAutosubmit`、`reloadProfiles(force: true)` 或 `reloadAutosubmit`。状态栏展示偏好直接复用现有完整缓存重算；用户名变化立即使旧账号缓存不可见并使旧请求失效，但远端读取延迟到下一次既有 `load()`/显式拉取，或最多做一次提交编辑后的防抖读取，不能逐键强刷。
3. 自动提交应用只执行 `configure/disable → status reload`，不刷新 profile batch，不推进统计 `fetchedAt`，不保存 General 草稿，也不关闭设置窗口。
4. 浮窗最小修复是只删除 `DashboardView` 根视图的 `.background(.background)`。不要再叠一层 SwiftUI `.regularMaterial`，也不要自建 `NSVisualEffectView`；AppKit 已为 popover 自动创建视觉效果背景，移除 380×680 的不透明覆盖后，箭头和主体由同一个系统 popover 表面呈现。

---

## 1. 当前保存流程及拆分边界

### 1.1 代码事实

- `SettingsView` 的 General、Autosubmit、About 都经过同一个 `settingsPage`，因此三个 Tab 都出现“保存”；按钮把 `enteredPreferences` 和 `enteredAutosubmit` 一起交给 ViewModel，并在成功后关闭窗口（`TokChan/Features/Settings/SettingsView.swift:79-110,127-152`）。Custom Pricing 没有经过这个容器（同文件 `:97-101`）。
- General 与 Autosubmit 草稿都是 `SettingsView` 的独立 `@State`，初始化时分别快照 `viewModel.preferences` 和当时的 `currentAutosubmitStatus`（同文件 `:25-39,49-76`）。之后 `.task` 才调用 `viewModel.load()`（`:116-119`），所以异步发现的用户名或后到的 autosubmit status 不会自动回填这些 `@State` 草稿。
- 当前 `saveSettings` 的顺序是：规范化偏好 → 校验 CLI context 和非空用户名 → configure/disable autosubmit → 使 profile/status 请求失效 → 账号变化时清空 profile 缓存 → 保存偏好 → 并发强刷整个 profile batch 与 autosubmit status（`TokChan/Features/Dashboard/DashboardViewModel.swift:353-401`）。
- `UserPreferences` 的全部字段都是小型 `UserDefaults` 偏好，store 的 `save` 是同步 setter 集合且没有失败返回（`TokChan/Shared/Services/PreferencesStore.swift:3-39,41-77`）。
- 状态栏标题已经是偏好与完整缓存的派生值，不会自行发请求（`DashboardViewModel.swift:102-120`）。Coordinator 订阅 incoming `preferences`，因此发布新偏好即可立即更新标题（`TokChan/Shared/StatusItemCoordinator.swift:169-181`）。
- profile API 只依赖 username；CLI context 只依赖 npx URL 与 Tokscale version（`DashboardViewModel.swift:438-470,590-614`）。
- 现有并发保护以 profile `generation/profileRequestID` 和 status `statusRequestID` 为边界；profile 响应还会校验当前 username（`DashboardViewModel.swift:83-86,453-470,504-519,528-534`）。
- 缓存契约明确要求账号变化先使 map 与 request generation 失效；autosubmit status 是机器本地状态，账号变化后仍可显示；status-only 保存不得推进统计 `fetchedAt`（`.trellis/spec/macos/data-persistence.md` 的 “Dashboard snapshot cache”）。
- Custom Pricing 每次操作从同一个 `PreferencesStoring` 重读 npx/version，并把变化视为 stale configuration；General 即时写入后该保护仍然成立（`TokChan/Features/Settings/CustomPricingViewModel.swift:77-105,133-140,191-209,284-295`）。

### 1.2 建议的 ViewModel API（实现推断）

函数名可按项目风格调整，关键是副作用边界：

```swift
// MainActor，同步；唯一副作用是偏好持久化、必要的本地失效和 @Published 发布。
func updatePreferences(_ mutate: (inout UserPreferences) -> Void)

// MainActor，异步；只处理自动提交远端/CLI 配置。
func applyAutosubmit(_ configuration: AutosubmitConfiguration) async -> Bool
```

更稳妥的 UI 接法是“每个 setter 基于 ViewModel 当前值做单字段 mutation”，而不是在每次 `onChange` 时把 `enteredPreferences` 整体快照送回。原因是后者可能用初始化时的空 username 覆盖 `load()`/`whoAmI` 刚发现并保存的 username。可以暴露字段级方法，或让 Binding setter 调用上述 mutation 闭包。

### 1.3 General 变更影响矩阵（实现推断）

| 字段 | 立即动作 | 禁止动作 | 后续读取策略 |
|---|---|---|---|
| `statusTextEnabled/template/period` | 保存并发布 `preferences`；模板字节原样保留 | CLI、profile/status reload、cache timestamp 变更 | Coordinator 用现有完整缓存立即重算标题 |
| `tokscaleVersion` / `npxPath` | 规范化后保存并发布；使旧的 in-flight status 结果失效 | profile cache 清空、profile 强刷、autosubmit configure/disable | 下一次 `load()`、显式 Autosubmit Apply 或 Custom Pricing reload 使用新 context |
| `username` | 规范化后保存并发布；若与旧值大小写不敏感比较后确为另一账号，则立即使 profile request generation 失效并清空账号绑定展示状态 | autosubmit CLI、更不能逐键强刷整个 profile batch | 下一次 panel `load()`/显式 Pull 读取新账号；若要求已打开 panel 自动恢复，只做一次编辑提交或防抖后的 read-only reload |

用户名变化时应同步清除：`cachedProfiles`、`profileState` 中的旧账号值、`identityProfile`、`cacheSavedAt`、`lastAutomaticAttempt` 和旧 profile error；保留 `selectedPeriod` 与 machine-local `autosubmitState/autosubmitObservedAt`。随后在新 `preferences` 生效后写一次不完整 snapshot，确保兼容字段 `profile` 也不把旧账号重新落盘。当前 snapshot 写入会从 `profileState.loadedValue` 和 `cachedProfiles` 组装兼容字段与 profiles（`DashboardViewModel.swift:616-640`），因此两处都必须先清空。

无需因 version/npx 改变而清 profile：远端 profile fetch 不使用 CLI context。应使已经发出的 status request 失效，避免旧 context 的结果晚到后冒充新 context 的观测结果；可继续显示之前已成功观测的 machine-local status 及时间戳，而不是把它当配置源。

### 1.4 “即时保存”不等于“逐键远端刷新”（实现推断）

- 每次文本变化可以立即写小型偏好并发布 UI 状态。
- profile/CLI 副作用必须与这个 setter 解耦。最小方案是在账号变化时立即隐藏旧账号数据，等现有 `panelDidAppear() → load()` 路径读取新账号（`DashboardViewModel.swift:200-211`）。
- 若设置窗口与已打开的 popover 可并存并要求自动恢复数据，应另设可取消、防抖且 generation-scoped 的 read-only account reload；它不能复用 `refresh()`，因为 `refresh()` 会先 submit（`:280-297`）。
- 不建议给展示模板做 debounce：它只需保存/重算现有数据，不访问外部系统。

### 1.5 并发边界（实现推断）

当前 General 控件在异步 operation 期间仍可编辑。拆分后需要二选一：

1. Autosubmit Apply 运行时禁用会改变 CLI context 的 General 字段；或
2. 引入 config generation：Apply 捕获 generation/context，CLI 返回后若 generation 已变化，不用旧 context 发布 status，并给出“操作可能已用旧配置执行，请重新应用/刷新”的准确反馈。

仅在字段 setter 中提前改一次 `statusRequestID` 不够：如果 Apply 在字段变化后才调用 `reloadAutosubmit(oldContext)`，该 reload 会创建新的 request ID。必须在 Apply 的 await 边界后再次比较 captured context/generation。

---

## 2. Autosubmit Tab 的显式 Apply

### 2.1 建议流程（实现推断）

```text
Apply tapped
  → guard no DashboardOperation is running
  → begin .applyingAutosubmit（替代语义过宽的 .savingSettings）
  → 从已即时持久化的 viewModel.preferences 构造 context
  → 保留现有非空 username 校验（R6 下不应顺手改变既有业务约束）
  → enabled ? configureAutosubmit : disableAutosubmit
  → reloadAutosubmit(context)
  → 成功/失败反馈留在 Autosubmit Tab；不 dismiss Settings
```

不得执行 `invalidateProfileRefresh()` 或 `reloadProfiles(force: true)`。Autosubmit mutation 不改变统计数据；`reloadAutosubmit` 已独立更新时间并调用 snapshot persistence（`DashboardViewModel.swift:504-519`），而 `persistCurrentSnapshot` 会保留旧 `cacheSavedAt/fetchedAt`（`:616-633`），符合 status-only 不推进统计新鲜度的契约。

UI 结构建议：

- General：普通 `Form`，无底部保存栏。
- Autosubmit：`Form` + 仅此 Tab 的 footer，包含 operation feedback 与“应用自动提交设置”按钮；默认键只在该 Tab 上属于该按钮。
- About：无 footer/action。
- Custom Pricing：保持自己的即时文件编辑/保存流程。
- Launch at Login：保持 toggle 直接调用 `LaunchAtLoginSettingsModel.setEnabled`，不纳入 Dashboard Apply。

### 2.2 Autosubmit 草稿同步是拆分后的必要修复（实现推断）

当前草稿在 `load()` 之前初始化。如果没有缓存，表单先取默认 disabled；稍后真实 status 即使为 enabled 也不会回填，用户点击新的 Apply 可能误关闭自动提交。

建议维护 `autosubmitDraft` + `isAutosubmitDirty`（或等价 baseline）：

- 有缓存 status 时同步初始化。
- 异步 status 首次到达时，仅在草稿尚未 dirty 时回填。
- 用户一旦编辑，不让后台 status 覆盖草稿。
- Apply 成功并重读 status 后，用确认结果更新 baseline，清 dirty。
- “立即运行”继续使用已保存配置，不读取 draft；现有帮助文案和 spec 已明确这一点（`TokChan/Features/Settings/AutosubmitStatusView.swift:36-42`）。

---

## 3. NSPopover 箭头与主体背景

### 3.1 Apple 主文档事实

- Apple 的 [`NSVisualEffectView`](https://developer.apple.com/documentation/appkit/nsvisualeffectview) 文档明确写明：AppKit 会自动为 window titlebars、**popovers** 和 source-list table views 创建 visual effect views，开发者“不需要”为这些元素再添加 visual effect view；material 还会随系统设置改变，因此应按用途选择而不是按表面颜色选择。
- [`NSVisualEffectView.Material.popover`](https://developer.apple.com/documentation/appkit/nsvisualeffectview/material-swift.enum/popover) 的定义就是“the material for the background of popover windows”。
- [`NSPopover`](https://developer.apple.com/documentation/appkit/nspopover) 自身拥有决定视觉特征的 appearance，并由系统相对 anchor 自动定位；当前 coordinator 已使用一个 `.transient` popover 和系统箭头（`TokChan/Shared/StatusItemCoordinator.swift:125-155,188-210`）。
- SwiftUI [`background(_:ignoresSafeAreaEdges:)`](https://developer.apple.com/documentation/swiftui/view/background(_:ignoressafeareaedges:)) 会把指定 style 画在 view 后方，并锚定到该 view 的 bounds。
- SwiftUI [`Material`](https://developer.apple.com/documentation/swiftui/material) 是另插入的一层平台混合/模糊材质，会随 light/dark 改变；它并不等于“复用 NSPopover 已存在的同一背景层”。

### 3.2 代码事实

- `DashboardView` 根 `VStack` 固定为 380×680 后，又对完整 bounds 应用 `.background(.background)`（`TokChan/Features/Dashboard/DashboardView.swift:49-53`）。因此内容矩形被 SwiftUI background style 覆盖，而箭头仍由外层 AppKit popover 绘制。
- popover 自身的 content size 也是 380×680、behavior 是 `.transient`，背景修复无需改 coordinator 尺寸或关闭行为（`StatusItemCoordinator.swift:145-155`）。
- Dashboard 内其他背景都只用于 metric/client card 等局部圆角元素，不会覆盖整个 popover surface（`DashboardView.swift:175-192,195-243`）。

### 3.3 最小修复（基于上述事实的推断）

删除且只删除根视图的：

```swift
.background(.background)
```

理由：让无自绘根背景的 SwiftUI 内容透出 NSPopover 已自动提供的 visual-effect surface，箭头与主体因此属于同一个系统 popover，而不是试图用第二层“看起来相近”的材质匹配箭头。

不建议：

- `.background(.regularMaterial)`：这是新增 SwiftUI 材质层，不能保证与 AppKit popover 箭头是同一 material/compositing context。
- 手工包 `NSVisualEffectView(material: .popover)`：Apple 明确说 popover 已自动创建视觉效果层；重复层可能改变透明度与 vibrancy。
- 修改 `popover.appearance`、自绘箭头、窗口圆角/阴影：均超出问题根因和 PRD 范围。

本机辅助验证（非 Apple 契约）：macOS 26.6.2 / Xcode 26.6 下，用 `NSHostingView` 与 `NSHostingController<AnyView>` 承载一个没有根 background 的 SwiftUI `VStack`，两者 `isOpaque == false`、layer background 为 nil。这支持“移除覆盖即可透出 AppKit 表面”的推断，但最终仍需真实 popover 在目标最低系统版本上视觉验收。

Apple 的 [`Settings`](https://developer.apple.com/documentation/swiftui/settings) 文档也以控件直接修改 `@AppStorage` binding 作为设置内容示例；这支持普通持久偏好的直接绑定模式，但它不是要求所有带 CLI 副作用的设置也必须即时执行，因此 Autosubmit 保留显式 Apply 合理。

---

## 4. 受影响测试

### 4.1 必须替换/改写

- `TokChanTests/DashboardViewModelTests.swift:375-415`
  - 当前测试锁定“configure 后同时 fetch + status”的旧全局保存语义。
  - 拆为：General update 零 CLI/零 fetch；Autosubmit enabled Apply 为 `configure,status` 且零 fetch；disabled Apply 为 `disable,status` 且零 fetch；统计 `cacheSavedAt` 不变。
- `TokChanTests/DashboardViewModelTests.swift:544-571`
  - 将旧 `saveSettings` 调用改成 General username update。
  - 继续断言旧账号 in-flight batch 不能发布；新增“更新本身没有发起 fetch”和“旧 profile 立即不可见/落盘 snapshot 不含旧账号 profiles”。
- `TokChanTests/DiscoveryRaceTests.swift:6-39`
  - 改用即时 General 更新入口。
  - 保留 suspended whoAmI 恢复后重新解析新 npx/version、不得覆盖新 username 的断言；根据新策略明确下一次 `load()`/防抖 read 的触发点。

### 4.2 应新增的 ViewModel / UI 状态测试

- 每类 General 字段即时 round-trip，并证明没有 `configure`、`disable`、`status`、`fetch`、`submit`。
- status text 三字段在完整缓存上立即改变 `statusItemTitle`；未知占位符语义继续由既有 renderer 测试覆盖。
- username 真变化清缓存并使旧 generation 失效；仅大小写变化不应误判为新账号。
- version/npx 变化保留 profile cache，但旧 context 的 late status 不能覆盖新观测语义。
- Apply 校验失败不执行 CLI；CLI mutation 失败不读 status；mutation 成功但 status read 失败时保留旧 status，并给出不谎称“未应用”的反馈。
- Autosubmit form：无缓存后 status 到达会初始化 pristine draft；dirty draft 不被后台 status 覆盖；成功 Apply 清 dirty。
- operation 互斥：Apply 运行中重复 Apply/Run Now 被拒绝；若 General context 仍可编辑，增加 captured-generation race 测试。
- Settings UI：General/About 无全局保存；Apply 只存在于 Autosubmit；Launch at Login 与 Custom Pricing 不依赖该按钮。建议给 Autosubmit Apply 添加稳定 accessibility identifier 后扩展 UI smoke test。

### 4.3 现有测试保持或补强

- `PreferencesStoreTests` 的 status-text round-trip/default/invalid-period 测试仍有效；若 normalization 移入 ViewModel，应另测 username/version/path trimming。
- `LaunchAtLoginSettingsModelTests` 业务测试应保持不变，因为 toggle 仍即时注册/注销。R4 的 enabled/notRegistered/notFound 文案移除属于 view presentation，可把 status-to-optional-message 抽成纯映射测试，或做 UI/人工检查；`requiresApproval` 跳转与错误测试必须保留。
- `DashboardLayoutTests` 仍应断言 light/dark 下 380×680。它把 Dashboard 放进 borderless `NSWindow`，没有真实 `NSPopover` 箭头（`TokChanTests/DashboardLayoutTests.swift:8-28`），因此不能证明接缝消失；移除根背景后若继续输出截图，应让 harness 提供 popover-like system backdrop，避免把透明 root 当回归。
- `TokChanUITests.testApplicationLaunchesAndMenuBarPanelClosesAndReopens` 已走真实 status-item/popover 路径并应继续通过，但没有像素断言（`TokChanUITests/TokChanUITests.swift:4-36`）。箭头/主体连续性仍按 AC5 在真实状态栏分别以 Aqua/Dark Aqua 人工验收。

## 最小实施文件范围（推断）

- 必改：
  - `TokChan/Features/Dashboard/DashboardViewModel.swift`
  - `TokChan/Features/Settings/SettingsView.swift`
  - `TokChan/Features/Dashboard/DashboardView.swift`
  - `TokChanTests/DashboardViewModelTests.swift`
  - `TokChanTests/DiscoveryRaceTests.swift`
- 很可能改：`TokChanUITests/TokChanUITests.swift`（验证 scoped Apply/无全局 Save）。
- 不需为背景修复改：`StatusItemCoordinator.swift`；其现有系统 NSPopover、380×680、`.transient` 行为正是要保留的背景所有者。
- 不应改业务语义：`PreferencesStore.swift`、`TokscaleCLIClient.swift`、`LaunchAtLoginSettingsModel.swift`、Custom Pricing store/CLI。仅当为测试或 UI binding 暴露更清晰入口时再做最小调整。

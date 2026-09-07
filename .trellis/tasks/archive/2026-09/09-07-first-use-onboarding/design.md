# 首次使用引导技术设计

## Scope and boundaries

本功能只扩展 Dashboard feature 的展示与编排状态，不建立新的全局 store，不改变 Tokscale API/CLI、缓存格式或偏好格式。`DashboardViewModel` 继续作为主线程上的异步编排边界；独立的 SwiftUI 子视图负责两步引导的布局与输入草稿。

预计影响：

- `TokChan/Features/Dashboard/DashboardViewModel.swift`：新增明确的首次引导状态与动作，复用现有偏好、CLI 和完整批次拉取边界。
- `TokChan/Features/Dashboard/DashboardView.swift`：在引导未完成时用引导内容替换正常 Dashboard 主体；普通已配置账号的错误态仍保留统计重试。
- `TokChan/Features/Dashboard/FirstUseOnboardingView.swift`：承载两步轻量 UI、用户名草稿、官网 Link、进度/错误反馈及 accessibility 标识。
- `TokChanTests/DashboardViewModelTests.swift`、`TokChanTests/DashboardLayoutTests.swift`：覆盖状态机、服务调用顺序、错误分流和固定尺寸渲染。

不新增第三方依赖，不更换 `NSStatusItemCoordinator` 对单一 `.transient` `NSPopover` 的所有权，也不绘制 Dashboard 根背景。

## State model

在 `DashboardViewModel` 中新增可测试、可比较的显式状态，例如：

```swift
enum FirstUseOnboardingState: Equatable {
    case discoveringIdentity
    case usernameEntry(message: String?)
    case verifying(username: String)
    case firstSubmission(username: String, message: String?)
    case submitting(username: String)
    case hidden
}
```

具体命名可在实现时按 Swift 风格微调，但必须保留以下语义：

- `discoveringIdentity`：仅用于无保存用户名时的现有 `whoami` 自动识别。
- `usernameEntry`：可手填用户名；错误属于身份发现或用户名拉取，不复用普通 ErrorState 的无效重试。
- `verifying`：保存/识别用户名后的强制完整批次拉取。
- `firstSubmission`：账号资料不存在或完整批次的 `.all.totalTokens == 0`。
- `submitting`：CLI 首次提交及其后的验证阶段，禁止重复操作。
- `hidden`：当前账号的完整批次 `.all.totalTokens > 0`，展示正常 Dashboard。

该状态不持久化。初始化时只读取现有偏好和完整、同账号的 Dashboard cache：

- 用户名为空：`discoveringIdentity`。
- 同账号完整缓存的 all Tokens 大于 0：`hidden`。
- 同账号完整缓存的 all Tokens 等于 0：`firstSubmission`。
- 有用户名但没有可判定的完整缓存：`verifying`，待 `load()` 完成后收敛。

账号变化继续复用现有 generation/request-ID 隔离并清除旧账号缓存；引导状态必须同步切回新账号的验证路径，不能展示旧账号结果。

## Data and action flow

### Automatic discovery

```text
popover show
  → panelDidAppear / load
  → username empty
  → resolve command context + cli.whoAmI
      success → normalize/save username → force/read complete batch → reconcile
      failure → usernameEntry(message)
```

自动发现失败不阻止用户直接填写用户名。现有 autosubmit 状态读取仍与统计独立，但不得覆盖引导错误或把引导误判为完成。

### Manual username

```text
username draft
  → trim + reject empty
  → updatePreferences (persist + account isolation)
  → verifying
  → forced complete batch fetch
      all.totalTokens > 0 → hidden
      all.totalTokens == 0 → firstSubmission
      profileNotFound → firstSubmission
      other error → usernameEntry(error)
```

`profileNotFound` 只在无可展示当前账号资料的首次验证路径中解释为“尚未提交”。普通已加载账号的后台/手动刷新仍按现有失败策略保留旧数据和诊断，不能把暂时的 404 变成引导回退。

### First submission

```text
firstSubmission
  → resolve existing npx/version context
  → cli.submit exactly once
  → force complete batch fetch exactly once
      all.totalTokens > 0 → hidden
      all.totalTokens == 0 → firstSubmission(explanatory message)
      profileNotFound → firstSubmission(explanatory message)
      other fetch error → firstSubmission(fetch error)
  → submit error → firstSubmission(submit error)
```

第二步提供返回第一步/修改用户名动作。返回时不清空保存值，只把当前用户名放回输入草稿；真正提交新值时才调用现有 `updatePreferences(_:)`。

## Result classification

现有 `ProfileReloadResult` 需要保留足够的类型信息，让引导区分：

1. 完整批次已更新；
2. `profileNotFound`；
3. 其他失败；
4. 请求被新 generation 取代。

不得只靠用户可见错误字符串反向判断错误类别。可为私有结果增加明确 case，或让内部错误包装保留 typed reason。正常 Dashboard 调用方仍将 `profileNotFound` 当作失败，只有首次验证编排层将其映射为第二步。

数据存在判断集中在 ViewModel 的单一 helper，使用完整同账号缓存中的 `.all.totalTokens > 0`，UI 不重复定义业务条件。

## View composition

`DashboardView` 保持固定 `380×680` 外框。根部根据 onboarding state 二选一：

- `.hidden`：渲染现有 header、范围 picker、metrics、breakdown 和 client scroll。
- 其他状态：渲染 `FirstUseOnboardingView`，使用系统 TextField、Button、Link、ProgressView、Label 和本地低对比度卡片背景。

引导内容保持轻量：顶部产品标识/简短说明，中部两步进度和当前操作，底部不新增全局 footer。长错误限制行数并提供 help，确保不会撑破固定浮窗。主操作支持默认键盘动作；输入框、主按钮、官网入口、修改用户名和错误反馈添加稳定 accessibility identifier。

## Compatibility and concurrency

- macOS 13：官网入口使用 `Link` 或等价系统 API，不依赖 macOS 14 的 `openSettings`。
- 不改变 `UserPreferences` 和 `DashboardCacheSnapshot` schema，因此无迁移。
- 所有 UI 状态变更保持在 `@MainActor`。
- 手工验证/首次提交必须继续使用现有 generation、request ID、operation-running guard；用户名变化或新动作开始时取消/忽略旧请求。
- 与已实施的缓存静默刷新策略兼容：完整正 Tokens 缓存可立即跳过引导；零 Tokens 缓存直接进入第二步；普通后台刷新不占用正常 Dashboard 的显式提交反馈。

## Risks and rollback

- Tokscale 对未提交用户名可能返回 404，也可能返回零统计；两者在首次验证中统一进入第二步，但提交后仍无资料时必须提示检查用户名，避免拼写错误形成假成功。
- API 刚提交后的可见性可能有延迟；提交命令成功但读取仍为零时保留可重试状态，不循环自动提交。
- `DashboardViewModel.load()` 已承担缓存、自动刷新、身份发现和 autosubmit 读取，新增状态必须避免第二套独立请求管线；优先在既有 reload 结果上做编排。
- 若需回滚，可删除引导子视图和 onboarding 状态/动作；偏好与缓存没有新增持久化字段，不需要数据回滚。

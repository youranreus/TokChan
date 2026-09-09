# macOS 后台只读统计刷新架构调研

## 结论

最小且可靠的方案是不新增独立 scheduler/service，也不把调度放进 popover coordinator。继续由长期存活、`@MainActor` 隔离的 `DashboardViewModel` 独占统计请求状态和一个调度任务；由 `TokChanApplicationDelegate` 只负责把应用启动与系统唤醒事件转交给它。

推荐边界：

1. `TokChanApplicationDelegate` 在应用启动后创建状态栏 coordinator、注册 `NSWorkspace.didWakeNotification`，启动一次应用级统计调度，并触发启动加载。
2. `DashboardViewModel` 提供幂等的 `startBackgroundRefresh()` 和只读的 `refreshStatisticsIfNeeded()`（名称可调整）。前者只允许一个长期任务，后者只调用现有 `reloadProfiles(force: false, automatic: true)`。
3. 唤醒事件直接调用一次 `refreshStatisticsIfNeeded()`，不补算休眠期间错过的 tick，也无需取消并重建原 timer。若 timer 同时到期，现有 `profileRefreshTask` 会合并请求；若刚失败，现有 `lastAutomaticAttempt` 会执行冷却。
4. `panelDidAppear()` / `panelDidDisappear()` 只保留面板可见性与 operation banner 的展示生命周期，不再启动或停止统计调度。
5. 保持 `TokscaleAPIService.fetchDashboardBatch`、`reloadProfiles`、generation/request ID、缓存发布逻辑不变。后台路径不得进入 `submit` 或 `runAutosubmitNow`。

该方案改动面最小，并且所有“同一时刻最多一个批次、强制刷新淘汰旧批次、账号隔离、失败保留旧值”的判断仍集中在一个地方。

## 当前结构与问题定位

### 应用生命周期

- `TokChanApplicationDelegate` 在初始化阶段创建并长期持有唯一 `DashboardViewModel`，见 `TokChan/TokChanApp.swift:5-10,52-58`。
- `applicationDidFinishLaunching` 当前只创建 `NSStatusItemCoordinator`，没有启动加载、后台 timer 或 wake observer，见 `TokChan/TokChanApp.swift:78-85`。
- `NSStatusItemCoordinator` 也长期持有同一个 view model，并订阅 profile 变化刷新菜单栏标题，见 `TokChan/Shared/StatusItemCoordinator.swift:158-180,339-354`。
- popover delegate 目前把 show/close 转成 `panelDidAppear` / `panelDidDisappear`，见 `TokChan/Shared/StatusItemCoordinator.swift:245-250`。

因此应用委托是正确的生命周期接线点，而 coordinator 应继续只负责状态栏与 popover 展示。

### 当前 timer 与面板错误耦合

- `DashboardViewModel` 已注入 `now`、刷新窗口、失败重试窗口和 async sleep，具备确定性调度测试所需 seam，见 `TokChan/Features/Dashboard/DashboardViewModel.swift:83-87,160-181`。
- `panelDidAppear` 先调用组合式 `load()`，成功返回且面板仍可见后才启动 timer；`panelDidDisappear` 会取消 timer，见 `DashboardViewModel.swift:226-250`。
- timer 循环本身也用 `isPanelVisible` 作为存活条件，见 `DashboardViewModel.swift:745-758`。这正是面板关闭后菜单栏数据不再更新的根因。
- 现有测试明确固化了旧行为“面板关闭后停止”，见 `TokChanTests/DashboardViewModelTests.swift:1192-1224`，需要改写而非保留。

### 已有一致性保证可直接复用

`reloadProfiles(force:automatic:)` 已经是应保留的唯一统计刷新入口：

- 非强制并发调用遇到 `profileRefreshTask` 时等待同一个 task，实现批次合并，见 `DashboardViewModel.swift:620-623`。
- 完整缓存未过期时跳过网络；自动失败后在 `retryInterval` 内跳过重试，见 `DashboardViewModel.swift:631-638`。
- 每个新批次记录 generation、request ID 和 username；成功或失败发布前都重新校验，见 `DashboardViewModel.swift:639-680`。
- 批次成功后一次性替换所有范围并更新 `cacheSavedAt`，失败时只写错误，不清空已有 profile，见 `DashboardViewModel.swift:658-680`。
- `invalidateProfileRefresh()` 同时递增 generation、替换 request ID、取消 task，见 `DashboardViewModel.swift:716-722`。用户提交前已调用它，而提交成功后的读取使用 `force: true`，见 `DashboardViewModel.swift:387-403`。现有竞态测试证明提交后的批次不会复用提交前的批次，见 `TokChanTests/DashboardViewModelTests.swift:1085-1112`。
- 账号变化会使旧批次失效并清空旧账号缓存；现有测试验证晚到响应不会发布，见 `DashboardViewModel.swift:460-478` 与 `DashboardViewModelTests.swift:1115-1159`。

不要在 AppDelegate 或新 scheduler 中再次维护 `isFetching`、时间戳、generation 或 request ID，否则会形成第二套状态机并破坏这些保证。

### 完整批次与请求成本

- `DashboardProfileBatch` 构造器要求四个本地 period 齐全且账号、period 匹配，见 `TokChan/Shared/Services/TokscaleAPIClient.swift:11-32`。
- live client 并行请求 `all`、`week`、`month` 三个远端范围，并由 week 派生 day，见 `TokscaleAPIClient.swift:76-90`。
- 现有 `PeriodAPITests.testBatchUsesThreeRevalidatedRequestsAndDerivesDayFromWeek` 已验证一次批次正好三个请求，见 `TokChanTests/PeriodAPITests.swift:40-56`。

后台调度必须调用 batch API，而不能按菜单栏当前展示 period 做单范围请求。

## 推荐 seam 与职责

### 1. DashboardViewModel：应用级 scheduler owner

建议将 `timerTask` 语义化重命名为 `backgroundRefreshTask`，保留为 view model 私有字段。

新增/调整接口：

- `func startBackgroundRefresh()`：同步、幂等；`guard backgroundRefreshTask == nil` 后创建循环。循环不检查 `isPanelVisible`。
- `func refreshStatisticsIfNeeded() async`：只调用 `_ = await reloadProfiles(force: false, automatic: true)`；不构造 CLI context，不调用 `load()`，因此不会读取 autosubmit 状态，更不可能上传。
- 可选 `func applicationDidWake()`：薄封装 `Task { await refreshStatisticsIfNeeded() }`；若希望 AppDelegate 明确管理 task，也可不设此方法。
- `deinit` 继续取消 profile 与 scheduler task。

循环建议继续采用“每轮重新计算下一次 deadline”的现有模式：

1. 根据完整快照 `cacheSavedAt` 算剩余 freshness。
2. 根据 `lastAutomaticAttempt` 算失败 cooldown。
3. sleep 一次。
4. 若当前有显式 operation，短暂等待后重新判断；否则走 `refreshStatisticsIfNeeded()`。

不要使用固定 `Timer` 每五分钟无条件 fetch。当前 deadline 算法能将网络量限制为成功批次约每五分钟一次，并在失败时按 cooldown 重试；每次成功批次成本为三个 HTTP 请求。

### 2. TokChanApplicationDelegate：生命周期桥接

在 `applicationDidFinishLaunching` 中：

1. 仍先幂等创建 `NSStatusItemCoordinator`。
2. 幂等注册 `NSWorkspace.shared.notificationCenter` 的 `NSWorkspace.didWakeNotification` observer，并保存 token，在 delegate deinit 时移除。
3. 调用 `viewModel.startBackgroundRefresh()`。
4. 启动一次 `Task { await viewModel.load() }` 作为 app-launch 事件。这样启动时可并行/组合读取过期统计与 autosubmit 状态；fresh cache 会跳过统计网络，但仍查询 autosubmit 状态。

Apple 的正式 seam：

- `NSApplicationDelegate.applicationDidFinishLaunching(_:)`: https://developer.apple.com/documentation/appkit/nsapplicationdelegate/applicationdidfinishlaunching(_:)
- `NSWorkspace.didWakeNotification`: https://developer.apple.com/documentation/appkit/nsworkspace/didwakenotification

wake observer 回调只触发一次 `refreshStatisticsIfNeeded()`。不记录 missed interval、不循环补跑，也不强制 fetch；是否读取完全由当前 `cacheSavedAt`、账号完整性和 cooldown 决定。

不建议仅依赖 SwiftUI `scenePhase`：当前应用的唯一 Scene 是 Settings，见 `TokChan/TokChanApp.swift:88-102`；菜单栏应用在设置窗口未打开时仍需接收生命周期事件。`NSWorkspace.didWakeNotification` 放在长期存活的 app delegate 更直接。

### 3. Popover 生命周期：只管展示

- `panelDidDisappear` 保留 banner suppression、presentation generation 与清理完成消息，但删除 scheduler cancel/nil。
- `panelDidAppear` 不再负责启动 scheduler。为满足 autosubmit 事件策略，建议也不再把组合式 `load()` 绑定到打开 dashboard 面板；应用启动已经完成首次加载。
- 若产品仍要求每次打开 dashboard 查询 autosubmit，则应明确写入事件策略；当前 PRD 的 R6 列出的是应用启动、打开设置、修改配置、立即运行，不包括打开 dashboard。

这能保证反复开关面板不会产生重复 timer 或重复统计批次，同时不破坏 `OperationBannerLifecycleTests` 所验证的展示行为。

### 4. Autosubmit 状态与统计刷新解耦

当前 `load()` 同时做身份发现、统计刷新和 autosubmit 状态读取，见 `DashboardViewModel.swift:266-311`；Settings `.task` 调用它，见 `TokChan/Features/Settings/SettingsView.swift:139-142`。

最小实现可保留 `load()` 作为“启动/打开设置”的组合入口，但后台 timer 与 wake 必须只走 `refreshStatisticsIfNeeded()`。这样：

- app launch 和 Settings 打开仍读取 autosubmit 状态；
- `applyAutosubmit` 与 `runAutosubmitNow` 已在动作后读取状态，见 `DashboardViewModel.swift:439-457,497-514`；
- 五分钟 timer 与 wake 不调用 `reloadAutosubmit`；
- autosubmit 状态失败仍与统计结果分开记录，现有 `reloadAutosubmit` 独立 request ID 和错误字段保持不变，见 `DashboardViewModel.swift:692-713`。

若实现过程中发现 `load()` 的 `isLoadingServices` guard 让事件语义难以测试，再做第二步小拆分：公开 `refreshAutosubmitStatus()`，让 Settings `.task` 显式并行调用统计 gate 与状态读取。不要为后台统计刷新提前做大规模 load/onboarding 重构。

## 启动、唤醒与竞态时序

### 应用启动

- coordinator 先订阅 view model，确保后续后台成功能更新 status item。
- scheduler 幂等启动。
- app-launch `load()` 立即按缓存年龄尝试一次；fresh 完整缓存不会产生三个 HTTP 请求，stale/缺失缓存只产生一个 batch。
- timer 即使已开始 sleep，也不会重复请求；下一轮会重新依据新 `cacheSavedAt` 计算。

### 系统睡眠与唤醒

不需要在 sleep 时累计 tick，也不需要在 wake 时重建 timer。wake 直接执行一次 freshness gate：

- 快照仍 fresh：零请求。
- 快照 stale：一个 batch（三 HTTP 请求）。
- timer 同时恢复并触发：`profileRefreshTask` 合并，仍只有一个 batch。
- 前一次失败仍在 cooldown：零请求；cooldown 后 scheduler 可恢复。
- wake 刷新成功后，旧 timer 将来醒来时先过 freshness gate，不会重复 fetch；随后按新 `cacheSavedAt` 重新排期。

### 手动操作交错

- 自动批次先发生、随后用户提交：提交入口先 `invalidateProfileRefresh()`，旧批次不能发布；提交完成后 `force: true` 建立新 generation。
- 用户提交先发生：`operation.isRunning` 阻止自动路径开始；提交后的强制读取优先。
- wake 与 timer 同时发生：非强制路径复用 `profileRefreshTask`。
- 仅拉取是 `force: true` 用户动作，应绕过自动 cooldown。

建议不要让 scheduler 自己调用 `invalidateProfileRefresh()`。自动动作应该合并而不是抢占，只有“本地数据刚提交”“账号变化”“用户明确强制拉取”才需要淘汰旧批次。

## 确定性测试建议

优先扩展 `TokChanTests/DashboardViewModelTests.swift` 的 `TestClock`、`ManualSleeper`、`EventRecorder`、`ControlledBatchAPI`，不要使用真实等待。

1. **面板关闭仍刷新**：启动 scheduler，面板从未打开；推进 clock 到 300 秒并释放 sleeper，断言恰好一个新 `fetch`、缓存时间与 status title 更新。
2. **开关面板不影响 scheduler**：scheduler 启动后反复 `panelDidAppear/Disappear`，推进一个窗口，只增加一个 fetch；不产生第二个 sleep loop。
3. **启动幂等**：连续调用 `startBackgroundRefresh()` 两次，只登记一个 sleep，窗口到期只产生一个 batch。
4. **fresh wake**：推进不足五分钟并调用 wake seam，断言无 fetch。
5. **stale wake / 不补跑**：模拟睡眠跨过多个五分钟窗口，wake 后只产生一个 batch，而不是按错过次数补跑。
6. **wake 与 timer 同时触发**：用 `ControlledBatchAPI` 挂起 wake 批次，同时释放 timer，断言 request count 仍为 1。
7. **失败与 cooldown**：保留旧完整快照，第一次 wake fetch 失败；断言 title/cacheSavedAt 不变。cooldown 内 timer/wake 均不重试，边界到达后只重试一次。
8. **无隐式上传**：启动、panel close、timer、wake 的 recorder 事件只能含 `fetch`（app-launch 若测试组合 load 可额外含 `status`），绝不能含 `submit` 或 `run`。
9. **后台批次与提交竞态**：自动 batch 挂起后开始 `refresh()`；断言旧自动响应不能发布、提交后 force batch 最终发布。可复用现有 `testManualMutationNeverReusesAPreMutationBatch`，但把第一个 load 改为后台触发。
10. **账号/generation 隔离回归**：后台请求挂起时改 username，旧响应不得恢复旧 title/cache；现有账号竞态测试应保留。
11. **panel banner 回归**：保留 `OperationBannerLifecycleTests`，证明移除 panel timer 职责后关闭面板仍只影响 banner，不取消正在进行的用户动作。
12. **AppDelegate lifecycle glue**：如果直接测试 AppDelegate 太重，提取一个很薄的可注入 wake-observing seam；至少验证 didFinish 只注册/启动一次，wake 转发一次。不要为此把完整 view model mock 成大协议。

测试工具风险：现有 `ManualSleeper` 使用 continuation 且不响应 task cancellation，见 `DashboardViewModelTests.swift:1550-1575`。如果测试需要取消/restart scheduler，必须显式 `advance()` 旧 continuation 或改造成 cancellation-aware sleeper；推荐架构无需在 wake 时重启 scheduler，可避免该复杂度。

## 风险与缓解

1. **组合式 `load()` 意外形成 autosubmit 轮询**  
   风险：若 timer/wake 继续调用 `load()`，每五分钟会执行 CLI `autosubmit status`，违反 R6。  
   缓解：后台入口只能调用 `reloadProfiles(force:false, automatic:true)` 的只读 wrapper。

2. **popover 打开仍重复读取状态**  
   风险：保留 `panelDidAppear -> load()` 会把 dashboard 打开也作为 autosubmit 状态事件，和最终 R6 列表不一致。  
   缓解：启动加载移到 AppDelegate，popover 仅保留展示职责；Settings `.task` 继续作为状态事件。

3. **重复 scheduler**  
   风险：didFinish、popover 与 wake 各自启动循环。  
   缓解：只有 app launch 调 `startBackgroundRefresh()`；方法用 task 是否存在做幂等；wake 只做一次 gate。

4. **新 scheduler 绕过 generation**  
   风险：直接调用 API 后赋值会允许旧账号或提交前响应覆盖新结果。  
   缓解：所有触发统一进入现有 `reloadProfiles`，不复制请求代码。

5. **operation 期间 busy loop**  
   当前 `nextAutomaticRefreshDelay()` 对 operation 返回 1 秒，见 `DashboardViewModel.swift:760-778`。长时间 CLI 操作期间会每秒唤醒一次，虽不发网络但有能耗。可保持现状以控制 scope，或使用一次轻量“operation ended 后重新评估”的 signal；不要为本任务引入复杂 event scheduler。至少验证不会发请求。

6. **无 username 的后台错误噪音**  
   `reloadProfiles` 在 username 为空时会设置 invalid username 错误，见 `DashboardViewModel.swift:624-630`。启动 onboarding 尚未识别身份时，timer/wake 不应抢先制造错误。启动时 `load()` 负责身份发现；只读 wrapper 可在 username 为空时直接跳过，或确保 timer 首次等待且 wake 与 load 合并。推荐显式空用户名 no-op，行为更稳。

7. **系统时间回拨**  
   当前 freshness 与 cooldown 对负 age 返回极短延迟，见 `DashboardViewModel.swift:724-727,760-778`。这不是本任务新增问题，但 wake 会增加遇到它的机会。可先保持现有策略；测试至少确保不会并发风暴。若后续强化，可将 wall-clock freshness 与 monotonic scheduling 分开处理。

8. **后台执行不是常驻保证**  
   macOS App Nap 或系统睡眠可能延迟 task；本需求可保证的是应用获调度、以及 wake 通知后按当前年龄补一次判断，不是严格每 300 秒实时执行。产品文案和测试应接受“约五分钟窗口 + 唤醒后一次判断”。

## 不建议的替代方案

- **把 timer 移到 `NSStatusItemCoordinator`**：它不了解 generation、failure cooldown、账号切换和用户操作优先级，会形成跨对象状态机。
- **新增 actor scheduler 并直接调用 API**：改动大且容易绕过 `@MainActor` 发布与现有请求合并；当前 view model 已有全部必要 seam。
- **每 5 分钟固定无条件 fetch**：增加三倍请求批次成本，忽略 cache age、失败 cooldown 与手动刷新刚完成的情况。
- **wake 时按休眠时长补 N 次**：数据接口只需要最新快照，补跑没有信息价值，只会制造请求风暴。
- **wake 时 force refresh**：会绕过 freshness/cooldown，和 R4/R7 冲突。

## 实现文件范围预估

核心架构预计只需触及：

- `TokChan/Features/Dashboard/DashboardViewModel.swift`
- `TokChan/TokChanApp.swift`
- `TokChanTests/DashboardViewModelTests.swift`
- 可能新增很小的 app lifecycle 测试文件

`TokChan/Shared/Services/TokscaleAPIClient.swift` 的 batch 语义不应修改；`TokChan/Shared/StatusItemCoordinator.swift` 仅在后续取消“只推送”入口和改文案时修改，不应承担后台 scheduler。

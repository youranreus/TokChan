# 后台刷新与提交状态设计审查

日期：2026-09-09

范围：当前源码、当前 Trellis 规范、归档的缓存刷新调研。未修改产品代码或规范，未执行真实网络请求、提交或 launchd 操作。

## 结论

三个产品方向可以组成一致模型，但不能只把现有面板计时器移到应用生命周期并改菜单文案。最小可行设计应明确分成两个互不依赖的通道：

1. **线上统计通道**：唯一的应用级调度器按完整快照的新鲜度读取 all/week/month，派生 day，整批发布；所有后台触发只进入此通道。
2. **Tokscale CLI 通道**：用户明确提交、运行自动提交、修改自动提交配置，以及按事件读取自动提交状态。状态失败不影响线上统计调度。

用户动作只保留以下语义：

- **仅刷新线上统计（不上传）**：强制读取一个完整统计批次。
- **提交本地用量并刷新统计**：先执行一次 `submit`；成功后强制读取一个新的完整统计批次。
- **立即运行自动提交**：执行一次 `autosubmit run --force`；成功后强制读取完整统计并重新读取自动提交状态。
- **应用自动提交设置**：配置/停用后只重新读取自动提交状态，不读取统计，因为它没有提交用量。

“刷新”应只表示读取；“提交”或“上传”必须显式出现于会上传的操作名称中。不要继续用“推送/拉取”作为主文案，也不要把单独的循环箭头当作上传动作的唯一提示。

## 当前行为

### 统计与面板生命周期

- `TokChan/Features/Dashboard/DashboardViewModel.swift` 的 `panelDidAppear()` 调用 `load()` 后启动 `timerTask`；`panelDidDisappear()` 取消计时器。因此面板关闭后没有新触发。
- 自动计时按 `cacheSavedAt` 的 300 秒 TTL 计算剩余时间，并用 `lastAutomaticAttempt` 实施 30 秒失败冷却。
- `reloadProfiles(force:automatic:)` 已具备完整批次发布、同账号验证、generation/request ID 隔离、旧数据保留和普通触发合并。
- `TokChan/Shared/Services/TokscaleAPIClient.swift` 每个批次并发发出 all/week/month 三个 HTTP 请求，week 同时派生 day；请求重验证缓存且单请求超时 30 秒。
- `TokChan/TokChanApp.swift` 由应用委托长期持有一个 `DashboardViewModel`，但启动时只安装状态栏协调器，不主动加载或启动应用级调度。

### 用户动作

- Dashboard 头部 `refresh()` 实际执行 `submit → 强制完整读取`，UI 是循环箭头，只有 tooltip/accessibility 文案说明上传。
- 右键“立刻推送”调用 `pushUsageNow()`，只 `submit` 不读取。
- 右键“立刻拉取”调用 `pullStatisticsNow()`，只强制读取完整批次。
- 首次用量 `submitFirstUsage()` 执行 `submit → 强制完整读取`。
- “立即运行”执行 `autosubmit run --force` 后，并发读取完整统计与自动提交状态。
- 自动提交设置应用成功后只读取一次状态，不改变统计 `fetchedAt`。

### 自动提交状态

- `load()` 把统计读取与 `autosubmit status --json` 放在同一入口；面板打开或 Settings `.task` 都可能调用它。
- 状态请求有独立 request ID、`autosubmitObservedAt` 和错误信息；状态读取失败不会撤销已成功发布的统计。
- 状态失败卡片的“重试”再次调用整个 `load()`，不是状态专用读取。
- Settings 中 General 的 npx/版本变更会使在途状态结果失效，但不会主动重新读取；缓存的旧状态仍可显示。

## 与现有规范冲突

本 PRD 有意改变已有合同，实施前后必须同步规范和测试，否则检查会互相否定。

1. `.trellis/spec/macos/swiftui-guidelines.md`
   - “Dashboard viewport contract”明确规定 popover 回调启动/停止五分钟计时器，关闭后停止未来触发。
   - “Configurable status-item usage text and manual transfer actions”规定 `pushUsageNow()` 只 submit、不 fetch，并保留 push/pull 两个菜单项。
2. `.trellis/spec/macos/data-persistence.md`
   - 生命周期测试要求“visible panel ticks and hidden panel schedules no additional reads”。
   - 仍把“on panel open”作为 TTL 检查的主要触发描述。
3. `.trellis/spec/macos/tokscale-integration.md`
   - 明确规定 status-menu push 只 submit，pull 只 fetch，且不得复用 combined operation。
   - “Base”案例规定打开面板并发读取 profile 与 autosubmit status；这与 R6 列出的事件策略不完全一致。
4. `.trellis/spec/macos/testing-guidelines.md`
   - 要求 hidden panel 不调度读取，并要求 push 恰好一次 submit、零 fetch。
5. 当前测试
   - `TokChanTests/DashboardViewModelTests.swift` 固化了 push-only、pull-only、面板关闭停止计时器。
   - `TokChanTests/SettingsWindowActionTests.swift` 的菜单 descriptor 固化 push/pull 两项。

应由新 PRD 明确 supersede 上述条款，并将“面板可见性”降为 banner/presentation 生命周期，而非数据调度生命周期。

## 关键遗漏与风险

### 1. “每五分钟刷新”必须定义为 TTL deadline，不是固定频率补跑

正确含义应是：以最后一次成功完整统计读取的 `fetchedAt` 为基准，在过期时尝试一次；成功后从新的 `fetchedAt` 重新计算下一期限。睡眠或 App Nap 导致错过期限时，唤醒后只重新评估一次当前年龄，不枚举错过的 tick。

不要同时保留 app-start load、panel-start timer 和另一个 status-title poller。应用启动只启动一个 scheduler；启动读取、面板打开、设置打开、唤醒和手动读取都进入同一个统计协调器。

### 2. 30 秒固定失败重试在后台常驻后成本过高

正常状态下三请求批次每五分钟意味着约 36 个 HTTP 请求/小时、864 个/天。若仍在失败时每 30 秒无限重试，最坏约 360 个请求/小时、8640 个/天，而且面板关闭不再限制它，明显与 R7 冲突。

最简单的后台策略是保留 30 秒作为第一次自动重试下限，再指数/分级退避到 1 分钟、5 分钟或更长；任一成功重置退避；用户的“仅刷新”绕过自动冷却。无需为了本任务引入第二套本地扫描或复杂 reachability 系统。

### 3. 睡眠唤醒需要明确事件入口

当前没有 `NSWorkspace` 睡眠/唤醒观察。仅依赖长期 `Task.sleep` 的实际系统行为难以满足确定性 AC5。应用级 scheduler 应接受一个 `wake`/`reevaluateNow` 事件；唤醒只取消当前等待并重新计算 TTL/cooldown。不要创建重复 scheduler，也不要按睡眠时长计算补跑次数。

### 4. “同一时间最多一个批次”与“取消后立刻强制读”需精确定义

当前手动提交开始时 `invalidateProfileRefresh()` 取消在途后台批次，然后提交；提交完成后启动新批次，结果隔离正确。可是若验收把“最多一个”解释为底层 HTTP 绝无短暂重叠，单纯 `cancel()` 后立刻启动还不够，因为旧 URLSession 子任务未必已完全终止。

建议合同写为：

- 协调器只有一个当前批次；普通读取合并到它。
- 提交开始时废弃并取消提交前批次。
- 提交后的强制读取必须等待旧批次结束/确认取消后再启动，且绝不复用提交前结果。
- 只有当前 request ID + generation + account 的完整批次可发布。

若只要求“最多一个可发布批次”，也应在 PRD/测试中明确，避免实现和验收对“网络层重叠”理解不同。

### 5. 账号切换竞态尚未统一

`refresh()` 在 submit 前解析账号，但 submit suspend 期间若 Settings 改了 username，后续 `reloadProfiles()` 会读取新 preferences，可能由旧操作触发新账号读取。`submitFirstUsage()` 已有 captured username 检查，普通提交没有同等保护。

统一提交操作应捕获 account/generation/CLI context。账号变化后旧操作不得读取或发布到新账号。此时“所有成功 submit 后都 pull”应有明确例外：账号已切换则旧操作结束为 superseded，不为旧账号做无用读取，也不能借旧操作读取新账号；新账号由自己的 scheduler/显式动作处理。

`runAutosubmitNow()` 也应防止 npx/version 在 CLI suspend 期间变化后，使用旧 context 发起一个新的状态请求并发布。状态 request ID 只能防住“先启动、后失效”的请求，防不住“context 已变后才用旧 context 启动”的请求；需要 context generation 或操作后重新解析 context。

### 6. 自动提交状态的事件清单仍有歧义

R6 的“修改配置”应明确仅指 autosubmit Apply 成功后的 status reread，还是也包括 General 的 npx/版本修改。两者目前行为不同。建议：

- app launch：读取一次 status；与统计并行且互不阻塞。
- Settings 真正变为可见：读取一次 status。
- autosubmit configure/disable 成功：读取一次 status。
- run-now 成功：读取一次 status。
- status 卡片手动重试：只读 status。
- panel open：不再是 status 事件，除非产品明确仍需要；若保留，就与“仅事件驱动且不随五分钟轮询”并不冲突，但必须写入 R6。
- npx/version修改：至少使当前展示标记为“来自旧上下文/待重新读取”，更简单的是修改完成后触发一次 status-only 读取；不要让它触发统计。

SwiftUI Settings 的 `.task` 是否会在“关闭后重新打开同一窗口”每次可靠重跑不应靠假设。需要把 settings-visible 事件做成可测试入口，并验证 raise 已存在窗口与重新创建窗口两条路径。

### 7. 状态读取和统计读取不应继续共用 `load()`

当前 autosubmit 失败卡片重试会调用 `load()`，可能顺带读统计；Settings 打开也会把两个通道绑定在一个 `isLoadingServices` guard 下。虽然内部 async let 能独立发布，但入口语义不清，事件丢失也更难测试。

应提供独立动作，例如：

- `startStatisticsScheduler()` / `reevaluateStatistics(trigger:)`
- `refreshStatisticsNow()`
- `refreshAutosubmitStatus(trigger:)`
- app startup orchestration 只并发调用两个独立入口

状态失败、缺少 npx 或 JSON 错误不得改变统计 scheduler、`cacheSavedAt` 或统计诊断。

### 8. 提交成功不等于公共 API 已包含新数据

服务端提交后的可见延迟没有合同保证。即使后续完整读取成功，也不应提示“全部范围已更新”来暗示刚提交的数据必然已出现。更准确的结果是“用量已提交，统计读取完成”；若读取失败则“用量已提交，但统计读取失败，当前仍显示上次成功结果”。首次提交仍需按现有合同在零 Tokens/404 时保留引导并提示稍后重试，不能自动重复提交。

### 9. 操作禁用与后台读取应区别

后台只读刷新不应让 Dashboard 的提交按钮转圈或禁用，也不应显示 banner；这是现有 cache-first 合同。用户显式“仅刷新”可以有自己的短暂状态，但全局 `DashboardOperation` 仍应保证两个显式动作不能并发。

菜单在后台批次运行时可保持显式动作可用：

- “仅刷新”可合并/升级为强制读取，或取消后台批次后重启；合同需择一。
- “提交并刷新”应抢占后台读取，提交后启动新批次。

“抢占”必须只影响统计请求，不能误取消无关的 autosubmit status 读取。

### 10. 最近读取时间与状态时间要严格分开

- `cacheSavedAt`/`fetchedAt` 只在完整统计批次成功后推进，供菜单栏和面板显示“统计读取于…”。
- `autosubmitObservedAt` 只在 status 成功后推进，显示“自动提交状态读取于…”。
- submit 成功但统计失败不能推进统计时间。
- 304/revalidated success 若成功产生完整批次，可以推进客户端成功读取时间；文案应称“读取于”，不要称“服务端更新于”。

右键菜单应始终动态显示最后成功统计读取时间；无成功快照时不要伪造时间。

## 建议的最小状态/触发模型

### 统计触发

| 触发 | 是否上传 | 是否绕过 TTL | 是否绕过自动失败冷却 | 行为 |
|---|---:|---:|---:|---|
| app 启动 scheduler | 否 | 否 | 否 | 按当前缓存年龄决定至多一次读取 |
| 300 秒 deadline | 否 | 否 | 否 | 过期才读 |
| 系统唤醒 | 否 | 否 | 否 | 重新评估年龄，只读至多一次 |
| panel 打开/关闭 | 否 | 否 | 否 | 不创建、停止或复制 scheduler |
| 仅刷新线上统计 | 否 | 是 | 是 | 强制一个完整批次 |
| submit 成功 | 是（前一步） | 是 | 是 | 强制使用提交后的新批次 |
| autosubmit run 成功 | 是（CLI 动作） | 是 | 是 | 强制完整批次 |

### 自动提交状态触发

| 触发 | 行为 |
|---|---|
| app 启动 | status-only |
| Settings 打开 | status-only |
| configure/disable 成功 | status-only，恰好一次 |
| run-now 成功 | status-only，恰好一次 |
| status 手动重试 | status-only |
| 五分钟统计 deadline / panel 开关 | 不读取 status |

### 优先级

1. 成功提交后的强制统计读取。
2. 用户“仅刷新”的强制读取。
3. app/wake/deadline 自动读取。

普通自动触发合并；高优先级触发不得复用提交前批次。账号或 context generation 变化使旧动作 superseded。

## 建议 UI 文案

右键菜单：

- `统计读取于 3 分钟前`（信息项）
- `提交本地用量并刷新统计`（会上传）
- `仅刷新线上统计（不上传）`（只读）

Dashboard：

- 上传动作 accessibility/help：`提交本地用量并刷新全部统计`
- 若继续使用 icon-only 按钮，循环箭头会与只读刷新混淆；优先改成含“提交”的文本按钮或明确上传图标与 tooltip。

Settings：

- `立即运行自动提交`，帮助文案增加“会上传本地用量，完成后刷新线上统计”。
- `状态读取于…` 保持仅指 autosubmit status。
- status 失败重试命名为 `重新读取状态`，不得调用全量 `load()`。

成功/部分成功：

- `用量已提交，统计读取完成。`
- `用量已提交，但统计读取失败；仍显示上次成功结果。`
- `线上统计已刷新（未上传本地用量）。`

## 必须补充的确定性测试

1. 应用启动且 panel 从未打开，TTL 到期后完整批次更新状态栏标题；事件序列无 `submit`/`run`。
2. panel 打开/关闭任意次数，scheduler 实例和 deadline 不改变，不产生重复批次。
3. wake 在 fresh cache 时零请求；stale 时一个批次；长睡眠不按错过周期补跑。
4. 自动失败保留旧批次；冷却/退避期间无请求；用户只读刷新立即绕过。
5. app-start、wake、deadline 同时触发只产生一个自动批次。
6. 后台批次 suspend 时点击提交：旧批次失效，`submit` 后恰好一个新批次可发布，旧结果不能覆盖。
7. 提交 suspend 时切换账号：旧操作不得读取或发布到新账号。
8. `submit` 失败时不读取；submit 成功但 fetch 失败时保留旧数据和旧 `fetchedAt`，反馈明确为部分成功。
9. 所有后台路径断言 CLI 事件中没有 `submit`、`autosubmit run`、configure 或 disable。
10. status 仅在启动、Settings 可见、Apply、run-now、手动 status retry 读取；五分钟 tick 不读 status。
11. status 失败与缺少 npx 不阻塞统计成功；统计失败也不删除已有 status。
12. npx/version 或账号/context generation 在 status/run suspend 时变化，旧 status 不能回写。
13. 菜单 descriptor 不再包含 push-only；只读与上传动作名称、排序、禁用状态及 accessibility 明确。
14. 后台静默读取不显示 banner、不使提交按钮转圈、不重置 scope；用户显式只读动作行为单独验证。

## 参考文件

- `.trellis/tasks/09-09-background-refresh-sync/prd.md`
- `.trellis/spec/macos/data-persistence.md`
- `.trellis/spec/macos/swiftui-guidelines.md`
- `.trellis/spec/macos/tokscale-integration.md`
- `.trellis/spec/macos/testing-guidelines.md`
- `.trellis/tasks/archive/2026-09/09-06-cache-refresh-strategy/research/cache-refresh.md`
- `TokChan/Features/Dashboard/DashboardViewModel.swift`
- `TokChan/Features/Dashboard/DashboardView.swift`
- `TokChan/Features/Settings/SettingsView.swift`
- `TokChan/Features/Settings/AutosubmitStatusView.swift`
- `TokChan/Shared/StatusItemCoordinator.swift`
- `TokChan/Shared/Services/TokscaleAPIClient.swift`
- `TokChan/TokChanApp.swift`
- `TokChanTests/DashboardViewModelTests.swift`
- `TokChanTests/OperationBannerLifecycleTests.swift`
- `TokChanTests/SettingsWindowActionTests.swift`

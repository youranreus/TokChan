# 后台统计同步设计

## Architecture

保留 `DashboardViewModel` 作为统计协调的深模块。它已经持有完整快照、请求任务、generation、账号、新鲜度和失败状态；后台调度必须进入同一个内部 `reloadProfiles(force:automatic:)`，不得在 AppDelegate 或状态栏协调器中复制请求状态。

模块对外只增加少量生命周期接口：

- `startBackgroundSynchronization()`：应用启动时调用，幂等启动唯一统计调度任务，并并发触发一次统计新鲜度评估与自动提交状态查询。
- `reevaluateStatisticsAfterWake()`：系统唤醒时调用一次普通自动评估，不强制请求、不补跑周期。
- `refreshAutosubmitStatus()`：Settings 显示、状态重试或 CLI 上下文变化时调用的 status-only 入口。

用户动作收敛为：

- `submitUsageAndRefreshStatistics()`：一次 CLI submit 成功后强制读取新完整批次。
- `refreshStatisticsNow()`：只读强制完整批次，不上传。
- `runAutosubmitNow()`：保留 run，成功后强制读取统计并查询状态。
- `applyAutosubmit(_:)`：配置成功后只查询状态。

首次使用继续复用现有身份发现流程。启动编排先启动唯一 scheduler，再并发进行自动提交状态查询与身份/统计准备：若已有有效 username，立即走普通统计新鲜度评估；若没有 username，只允许一次 `whoami` 发现，成功保存规范化 username 后必须立即重新评估统计，失败则进入现有手动用户名引导。身份发现完成前的 timer/wake 评估为 no-op，不能制造 invalid-username 诊断、重复 `whoami` 或隐式上传。

## Ownership and Lifecycle

`TokChanApplicationDelegate` 是应用生命周期桥接点：

1. 创建并保留唯一 `NSStatusItemCoordinator`，确保后台发布前订阅已建立。
2. 注册一次 `NSWorkspace.didWakeNotification` 并保存 observer token。
3. 调用 `viewModel.startBackgroundSynchronization()`。
4. 唤醒时转发到 `reevaluateStatisticsAfterWake()`；delegate 销毁时移除 observer。

`NSStatusItemCoordinator` 继续只负责 AppKit 状态栏、菜单和 popover 展示。`panelDidAppear()` / `panelDidDisappear()` 只管理 `isPanelVisible`、banner generation 和反馈清理，不再启动或取消统计任务。Dashboard 打开不再查询自动提交状态。

Settings 窗口每次从不可见变为可见时调用一次 status-only 入口，包括新建窗口和重新前置已存在窗口；同一段连续可见期间的 SwiftUI 重绘、tab 切换和重复回调必须合并，不重复查询。由 Settings 窗口展示路由发出可测试的 visibility 事件，SwiftUI `.task` 只负责首次挂载兜底，不能把组合式 `load()` 重新引入。自动提交状态卡片的重试也只重读状态，不触发统计。

## Statistics Scheduler

调度含义是基于 deadline 的 stale-while-refresh，不是固定每 300 秒无条件请求：

1. 启动后立即调用普通自动评估。
2. 根据最后成功完整批次 `fetchedAt` 计算剩余 300 秒。
3. 到期时调用 `reloadProfiles(force: false, automatic: true)`。
4. 成功后从新 `fetchedAt` 重新计算 deadline。
5. 显式操作运行中不发起后台请求；操作结束后重新评估。

普通自动触发包括 app start、deadline 和 wake。它们共享在途 `profileRefreshTask`，fresh 快照直接返回。用户只读刷新使用 `force: true`，绕过 TTL 和自动退避。用户提交开始前废弃并取消提交前统计批次；提交成功后只允许新的强制批次发布。

### Failure backoff

用单一自动失败状态记录连续失败次数或 `nextAutomaticAttemptAt`：

- 第一次失败后至少等待 30 秒。
- 第二次失败后至少等待 60 秒。
- 第三次及以后至少等待 300 秒。
- 成功完整批次后清零。
- fresh/superseded/因显式 operation 跳过不计为失败。
- 用户主动读取不受该退避限制，但失败不应缩短已有后台退避。

所有 app start、deadline 和 wake 自动路径都检查同一退避状态。系统时间回拨时做安全的近期重新评估，但不得形成无延迟循环。

## Autosubmit Status Channel

自动提交状态与统计通道彻底分离：

| 事件 | 状态查询 |
| --- | --- |
| app start | 一次 |
| Settings 显示 | 一次 |
| configure/disable 成功 | 一次 |
| run-now 成功 | 一次 |
| 状态卡片手动重试 | 一次 |
| npx/版本上下文改变 | 使旧请求失效并触发一次新上下文查询 |
| 300 秒统计 deadline / wake / Dashboard 开关 | 不查询 |

状态使用独立 request ID、observedAt 和错误。CLI 上下文改变时，迟到状态不可发布；旧上下文中的显式操作结束后不得用旧 context 启动新的状态查询。

## Manual Operation Semantics

右键菜单改为两个可见且无歧义的动作：

1. `提交本地用量并刷新统计`
2. `仅刷新线上统计（不上传）`

Dashboard 上传入口继续适应 380 点宽度，但可见标签、help 和 accessibility 中必须出现“提交”或“上传”，不能只用循环箭头表达上传。自动提交按钮使用“立即运行自动提交”，帮助文本明确会上传并刷新线上统计。

提交成功后的提示使用“用量已提交，统计读取完成”，不使用“全部范围已更新”来暗示公共 API 已包含刚提交的数据。提交成功但读取失败时说明仍显示上次成功结果。

提交类操作捕获开始时的账号、generation 与 CLI context。挂起期间若账号或 CLI context 改变，旧操作结束为 superseded：不为新账号读取，不用旧 context 查询状态，也不发布误导性成功反馈。

## Data Flow

```text
App launch ─┬─> start one statistics scheduler ─> freshness/backoff gate ─> existing full batch loader
            └─> status-only CLI query

300s deadline ────────────────────────────────> freshness/backoff gate
NSWorkspace wake ─────────────────────────────> freshness/backoff gate

Submit action ─> invalidate pre-submit batch ─> CLI submit ─> forced new full batch
Read-only action ──────────────────────────────────────────> forced full batch
Autosubmit run ─> CLI run ─┬───────────────────────────────> forced full batch
                            └───────────────────────────────> status-only query
```

完整批次成功仍一次性替换 all/day/week/month、推进 `fetchedAt`、持久化快照并通过现有 Combine 订阅更新状态栏。状态成功只推进 `autosubmitObservedAt`。

## Compatibility and Spec Migration

不修改 API client、快照 schema、Tokscale scheduler 或远端接口。新行为有意替换以下旧合同：

- `data-persistence.md`：隐藏面板不再停止统计调度；生命周期测试改为 app-level scheduler。
- `swiftui-guidelines.md`：popover callback 不再拥有 timer；push/pull 菜单合同改为提交并刷新/仅刷新。
- `tokscale-integration.md`：删除 push-only 约束和“combined operation 是 bad case”的描述。
- `testing-guidelines.md`：替换 hidden-panel-zero-read、push-zero-fetch 断言，并加入 app start/wake/backoff/status-event 测试。

保持 macOS 13、单一 AppKit 状态项、380×680 Dashboard、完整批次缓存和 Application Support JSON 格式兼容。

## Rollback

改动不迁移或删除用户数据，也不修改远端或 launchd 配置。若后台生命周期不可靠，可回滚 AppDelegate 接线与 view-model scheduler，同时保留手动操作命名改进；若手动语义回滚，必须同步回滚对应规范和测试，不能恢复代码后留下相反合同。

# 实施与验证计划

## Ordered Checklist

1. 在实施前加载 `trellis-before-dev` 与 macOS 的 state management、data persistence、networking、SwiftUI、Tokscale integration、testing、quality 规范；明确本任务取代的旧 lifecycle 与 push-only 合同。启动相关测试先覆盖已有 username，以及空 username 时 `whoami` 成功后恰好一次统计评估、失败进入手动引导。
2. 先更新/新增 `DashboardViewModelTests` 的失败用例，覆盖应用级调度器幂等、面板关闭仍按 300 秒刷新、panel 开关不影响调度、无 username no-op 和后台路径零 CLI mutation。
3. 将 `DashboardViewModel` 的 panel timer 改为唯一应用级统计 scheduler；保留现有 full-batch loader 作为唯一统计请求实现，增加 app start 与 wake 的薄接口，不在 AppDelegate 复制请求状态。
4. 实现自动失败分级退避 30 秒→60 秒→300 秒并封顶，成功重置；补充 fresh/superseded/手动操作不错误累计、clock rollback 不 busy-loop 的确定性测试。
5. 在 `TokChanApplicationDelegate` 完成启动接线与 `NSWorkspace.didWakeNotification` observer 生命周期；验证 status coordinator 先订阅、scheduler 只启动一次、wake 只做一次 freshness gate。
6. 拆分 autosubmit status-only 入口：app start、Settings 窗口每次从不可见变为可见、状态重试、配置/停用成功、run-now 成功、npx/版本改变触发；同一段 Settings 可见期内合并重复事件，统计 deadline、wake、Dashboard 开关不得读取 status。
7. 统一用户手动操作接口和竞态保护：提交并刷新、仅刷新线上统计、立即运行自动提交。捕获账号/generation/CLI context，防止挂起期间上下文变化后为错误账号读取或发布。
8. 更新 `StatusMenuDescriptor`、右键菜单、Dashboard 上传入口、autosubmit run/status retry 文案与 accessibility/help。删除只推送入口；成功与部分成功反馈不得暗示服务端已包含刚提交数据。
9. 保留并扩展现有 batch、缓存、账号隔离、operation banner、状态栏 Combine 发布测试；新增 submit 失败时零读取、submit 成功但读取失败时保留旧快照/`fetchedAt` 并显示部分成功反馈的确定性测试；更新所有 fake/preview 调用点及旧 push-only/hidden-panel 断言。
10. 使用 Debug fixture 做 UI/交互验证：面板关闭期间后台模型更新能改变状态栏标题；左右键、Settings 重开、380×680 Dashboard、长用户名、明暗模式和无网络错误展示不回归。UI 测试不得访问真实网络、npx 或 launchd。
11. 运行全量单元测试与 Release 构建；执行 `trellis-check` 做规范、并发、跨层数据流和回归审查。
12. 使用 `trellis-update-spec` 同步 `data-persistence.md`、`swiftui-guidelines.md`、`tokscale-integration.md`、`testing-guidelines.md`；确认规范不再保留 hidden-panel-stop 或 push-only 的相反合同后提交收尾。

## Validation Commands

```sh
xcodebuild test \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/TokChan-background-refresh-test

xcodebuild \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -configuration Release \
  -destination 'platform=macOS' \
  -derivedDataPath /private/tmp/TokChan-background-refresh-release \
  build
```

如仓库没有 SwiftLint 配置则不臆测新增 lint 命令。UI 自动化只使用 `--ui-testing` 离线依赖。

## Review Gates

- 后台 timer、app start 与 wake 全部通过同一个统计协调入口；panel 生命周期完全不触发统计，只保留展示反馈职责。
- 任一后台事件都不能记录 submit/run/configure/disable。
- 五分钟定义为成功 `fetchedAt` 的 deadline；睡眠和 App Nap 不补跑。
- 失败退避不会在面板关闭时形成 30 秒永久请求风暴。
- 手动 submit 后的批次不能复用提交前请求；上下文级别检查确认取消请求不会发布旧结果。
- autosubmit status 不随统计 tick 或 Dashboard 开关运行，且 status-only 重试不顺带拉统计。
- `fetchedAt` 与 `autosubmitObservedAt` 的推进源严格分开。
- 所有本任务有意改变的规范与测试断言同步更新。

## Risky Files and Rollback Points

- `TokChan/Features/Dashboard/DashboardViewModel.swift`：scheduler、退避、请求竞态与上下文隔离。先让确定性模型测试通过，再接 AppKit 生命周期。
- `TokChan/TokChanApp.swift`：应用启动与 wake observer。observer token 必须幂等注册并在销毁时移除。
- `TokChan/Shared/StatusItemCoordinator.swift`：菜单 descriptor 与用户动作路由；保持唯一临时 NSMenu 和现有左右键行为。
- `TokChan/Features/Dashboard/DashboardView.swift`、`Features/Settings/*`：紧凑布局、可见文案与 status-only 入口。
- `TokChanTests/DashboardViewModelTests.swift` 及 lifecycle/menu tests：ManualSleeper 当前取消不敏感，若测试无需重启 scheduler 则不要扩大测试工具改造。

代码改动不触碰缓存 schema、用户统计数据、远端 API 或 launchd 配置，可按“模型调度 → AppDelegate 接线 → UI 语义”三个阶段分别回滚。任何行为回滚必须连同相应测试和规范合同一起回滚。

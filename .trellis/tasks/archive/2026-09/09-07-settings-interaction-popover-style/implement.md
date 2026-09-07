# 实施与验证计划

## Preconditions

- 从 `master` 创建本任务工作分支并以 `master` 为 PR 目标；随后按原提交顺序纳入 `feat/status-text-and-actions` 相对 `master` 的已完成提交（含功能、测试与 spec），再实施本任务改动。
- 实施前加载 `trellis-before-dev`，并阅读 manifests 中的 macOS 规范与 `research/settings-save-and-popover.md`。
- 保持任务状态为 planning，直到用户明确批准本规划摘要后再运行 `task.py start`。

## Implementation Checklist

1. **建立可验证的新设置接口**
   - 先改写/新增 `DashboardViewModelTests`，分别锁定 General 更新零 CLI/零网络副作用、用户名跨账号失效、version/npx 保留 profiles，以及 Autosubmit Apply 的 configure-or-disable + status-only 顺序。
   - 在 `DashboardViewModel` 增加同步 `updatePreferences`，集中规范化、账号缓存失效、旧 status request 失效、UserDefaults 保存和 published 更新。
   - 用 `applyAutosubmit` 替换混合的 `saveSettings`；将 operation case 和反馈文案收敛为“应用自动提交设置”，不 refresh profiles、不 submit、不 dismiss。
   - 更新 Discovery/并发测试，证明旧账号请求不能晚到、偏好逐次变化不发起请求、status-only 保存不推进统计 `fetchedAt`。

2. **重构 Settings 的所有权与布局**
   - General 控件改为基于 `viewModel.preferences` 当前值的即时 Binding，删除 username/version/npx/status-text 的整组旧草稿与 `enteredPreferences`。
   - 基本配置和 npx 在显式 operation 期间禁用；状态栏文案仍可即时修改。
   - 将 Section 排序改为“基本配置 → 状态栏文案 → 启动 → npx”，设置模板说明为精确文案“支持的模板变量：{token}、{cost}”。
   - 删除共享 footer 和 `dismiss` 依赖；General/About 无 action，Autosubmit 独立 footer 显示“应用自动提交设置”。
   - 为 autosubmit draft 增加 pristine/dirty 同步，后到 status 只回填未编辑草稿，Apply 成功后用确认状态回填并清 dirty，失败保留草稿。
   - 简化登录项状态呈现：enabled/notRegistered/notFound 返回 EmptyView，保留 updating/error/requiresApproval 反馈和恢复入口。

3. **修复 popover 根背景**
   - 先确认 `NSStatusItemCoordinator` 仍使用一个系统 `.transient` `NSPopover`，尺寸 380×680。
   - 只删除 `DashboardView` 根 `.background(.background)`；不添加 SwiftUI Material、`NSVisualEffectView` 或自绘 arrow/chrome。
   - 保持 metrics/client/banner 等局部背景不变，并复跑 layout/UI smoke tests。

4. **补齐呈现与回归测试**
   - 更新 Settings UI smoke test/accessibility identifiers，确认 General/About 不存在全局保存，Autosubmit 只有 scoped Apply。
   - 覆盖 autosubmit status 后到时 pristine draft 回填、dirty draft 不覆盖和成功 Apply 清 dirty。
   - 保留并复跑 PreferencesStore、StatusItemTextRenderer、StatusItemCoordinator、LaunchAtLogin、CustomPricing、Dashboard layout/cache/operation 测试。
   - 浅色与深色分别手动检查真实状态栏 popover：箭头与主体材质连续、尺寸/圆角/阴影正常、点击外部关闭正常；同时检查四个 General Section 顺序和删减后的文案。

5. **质量检查与收尾**
   - 运行聚焦测试后执行全量 unit/UI tests、Universal Release build、Debug Analyze 和 `git diff --check`。
   - 派发 `trellis-check` 做 spec 与 PRD 双轴检查；任何问题修复后重跑受影响及最终全量验证。
   - 使用 `trellis-update-spec` 将“普通偏好即时持久化、autosubmit scoped apply、NSPopover 根背景所有权”同步到 macOS spec；不把一次性文案排序写成过度泛化规则。
   - 按 Trellis finish 流程提交任务代码、spec、task/journal 并归档。

## Validation Commands

```sh
# 聚焦 model / settings / status item tests（具体 test identifiers 按实现后的 XCTest 名称调整）
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-settings-detail-test -only-testing:TokChanTests/DashboardViewModelTests -only-testing:TokChanTests/DiscoveryRaceTests -only-testing:TokChanTests/PreferencesStoreTests -only-testing:TokChanTests/SettingsWindowActionTests -only-testing:TokChanTests/StatusItemTextRendererTests

# 全量单元测试
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-settings-detail-test -only-testing:TokChanTests

# UI smoke tests；SystemUIServer 不暴露状态项时必须明确 skip
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-settings-detail-ui-test -only-testing:TokChanUITests/TokChanUITests

# Release / Analyze
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -destination 'generic/platform=macOS' ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO -derivedDataPath /private/tmp/TokChan-settings-detail-release build
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-settings-detail-analyze analyze

git diff --check
```

## Risky Files and Review Gates

- `TokChan/Features/Dashboard/DashboardViewModel.swift`：跨账号 cache/generation 失效、零副作用 General 更新、status-only autosubmit apply 和 operation 互斥。
- `TokChan/Features/Settings/SettingsView.swift`：即时 Binding 不得用旧整组快照覆盖新 preference；autosubmit dirty draft 不得被异步状态覆盖。
- `TokChan/Features/Dashboard/DashboardView.swift`：只移除根背景，避免误删局部可读性背景或改变 380×680 viewport。
- `TokChanTests/DashboardViewModelTests.swift` / `DiscoveryRaceTests.swift`：必须证明命令隔离、账号竞态和快照新鲜度。
- `TokChanUITests/TokChanUITests.swift`：只能使用 fixture dependency，不访问真实网络、npx 或 launchd。

在完成 ViewModel 测试、Settings 接线、背景一行修复后分别形成检查点；若任一步导致不可恢复的回归，回退该步而不是用额外状态层或第二层材质补丁绕过。

## Rollback Shape

- General/Autosubmit 拆分可恢复原 `saveSettings` 和 footer；没有 UserDefaults schema 或远端迁移。
- Popover 修复可单独恢复根 `.background(.background)`，不影响设置接口。
- 若真实最低系统视觉验收证明透明 SwiftUI root 未透出 AppKit surface，停止在该检查点重新研究 hosting 配置，不用近似颜色或自绘箭头掩盖接缝。
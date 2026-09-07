# 实施与验证计划

## 实施清单

1. 加载 `trellis-before-dev` 与 manifests 中的 macOS 规范、任务 PRD/设计和调研；确认不破坏唯一 coordinator、完整缓存批次及 Tokscale 命令边界。
2. 先增加纯 `StatusItemTextRenderer` 及单元测试，覆盖 token/cost、多次出现、未知变量原样保留、普通文本、空模板、零值与既有格式化。
3. 扩展 `UserPreferences` 与 `UserDefaultsPreferencesStore`，增加默认关闭、默认模板和默认日范围；测试 round-trip、旧键缺失和无效 period 回退，并更新所有测试/Preview fixture 初始化。
4. 在常规设置增加状态栏 Section：Toggle、模板 TextField、全部/日/周/月 Picker；并入现有本地编辑状态、`enteredPreferences` 与统一保存，不增加校验 UI。
5. 为 `DashboardViewModel` 增加只读状态栏文案计算入口，严格读取已缓存指定范围；无缓存/空结果返回 nil，旧缓存刷新时继续可读，不发起独立请求。
6. 让 `NSStatusItemCoordinator` 观察已保存偏好与缓存发布并同步按钮：在 nil 与非空标题间切换 square/variable length，保持图标领先、tooltip 和 accessibility；覆盖冷启动同步与设置保存后的更新。
7. 扩展 menu descriptor 与构建测试，加入“立刻推送”“立刻拉取”、稳定分隔顺序和基于 `operation.isRunning` 的启用状态。
8. 在 ViewModel 实现 push-only 与 pull-only：push 只执行一次 CLI submit，pull 只强制读取一次完整批次；接入 coordinator action，清理成功后的同类旧诊断，并把失败导向刷新详情。
9. 增加 view-model 测试证明 push 无 profile fetch、pull 无 submit、失败诊断可见、成功安静、重复/并发操作被拒绝，且既有 refresh 与 autosubmit 行为不变。
10. 更新状态栏与设置相关测试/Preview/UI fixture；检查明暗外观、超长/空/未知变量模板、无缓存、旧缓存刷新失败、四个范围与左右键菜单交互。
11. 运行全量测试、Release 构建、Analyze（若项目现有流程支持）和 `git diff --check`；随后派发 `trellis-check`，修复问题并重跑受影响验证。
12. 使用 `trellis-update-spec` 同步状态栏动态标题、偏好键和即时推拉契约；提交并按 Trellis 流程归档。

## 验证命令

```sh
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-status-text-test
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-status-text-ui-test -only-testing:TokChanUITests/TokChanUITests
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-status-text-release build
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Debug -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-status-text-analyze analyze
git diff --check
```

## 高风险文件与检查点

- `TokChan/Shared/StatusItemCoordinator.swift`：状态项长度/标题、Combine 生命周期、原生动态菜单和 selector action。
- `TokChan/Features/Dashboard/DashboardViewModel.swift`：缓存读取、operation 互斥、push/pull 严格分离及诊断生命周期。
- `TokChan/Shared/Services/PreferencesStore.swift`：默认值、旧版本兼容及所有构造点。
- `TokChan/Features/Settings/SettingsView.swift`：本地编辑状态与统一保存，避免未保存设置提前影响状态栏。
- `TokChanTests/SettingsWindowActionTests.swift`、`DashboardViewModelTests.swift`、`PreferencesStoreTests.swift`：菜单顺序、命令隔离和持久化回归。

## 回滚点

先完成纯渲染器、偏好与 view-model 测试，再连接 AppKit 状态项。若 variable-length 标题在最低系统上出现经验证的布局阻断，可暂时回滚 coordinator 标题绑定而保留偏好/渲染测试；若即时操作与现有 operation 状态冲突，回滚菜单入口而不改动原 `refresh()`、`retryStatistics()` 和 `runAutosubmitNow()`。不得以独立网络轮询或第二个 view model 规避问题。

## 实施结果（2026-09-07）

- 已实现默认关闭的状态栏文案偏好、`{token}` / `{cost}` 字面模板渲染、全部/日/周/月范围选择和 UserDefaults 向后兼容；状态栏 `{cost}` 固定使用 `$` 前缀，不改变 Dashboard 的本地化货币格式。
- 唯一 coordinator 订阅已保存偏好与缓存发布，在 square/variable length 间切换并同步可访问名称；有文案时基于 AppKit 原生 attributed title 添加 `-1pt` baseline offset，使文字与图标视觉对齐且不影响 icon-only 模式；检查阶段修复了 `@Published` 在 `willSet` 发出新值时重读旧 preferences 导致标题滞后的问题。
- 右键菜单已加入安静执行的“立刻推送”“立刻拉取”：前者只 submit，后者只强制完整批次读取，运行中统一禁用，失败进入刷新诊断。
- 原功能最终验证：42 个聚焦测试与 145 个全量单元测试通过；2 个 UI 测试因 SystemUIServer 不暴露状态项而明确跳过；Universal Release 构建和 Debug Analyze 成功，日志无编译器/分析器警告，`git diff --check` 通过。
- 本次视觉与货币前缀微调验证：39 个相关测试通过，更新 AppKit 属性保留断言后 6 个 presentation 测试复跑通过；Debug 构建与 `git diff --check` 通过。

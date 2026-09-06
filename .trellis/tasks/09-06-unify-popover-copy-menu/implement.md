# 实施与验证清单

状态：已实施并通过自动化验证。

1. 加载 `trellis-before-dev` 及 manifests 中的 macOS 规范和本任务调研；确认本任务明确替换旧规范中的固定 footer 与 `MenuBarExtra(.window)` 所有权描述。
2. 先提取并测试统一数据新鲜度 formatter：快照成功获取时间为唯一“更新于”，跨日附服务端实际数据日期，无快照不伪造文案。
3. 增加可测试的状态栏菜单 descriptor、settings action 与点击路由；覆盖动态时间、诊断入口、设置、退出及左/右键分支。
4. 实现唯一的 `NSStatusItemCoordinator`：公开 AppKit API路由左右键，长期持有 transient `NSPopover`/hosting controller，右键关闭浮窗后展示动态 `NSMenu`，保留图标模板和“TokChan”可访问名称。
5. 调整 app composition：以 `NSApplicationDelegate` 安装 coordinator 并共享现有模型，移除 `MenuBarExtra`，保留 SwiftUI `Settings` scene 和 Preview/UI-testing 服务注入。
6. 将面板显示/关闭生命周期唯一迁移到 popover delegate；移除 DashboardView 的重复回调，验证定时刷新仅在可见期运行且左键/外部点击/右键替换均只产生一次关闭。
7. 精简 DashboardView：删除 footer 和旧 settings/quit/diagnostics UI；头像区移除 `profile.updatedAt`，保留 `@username` 并低调显示共享新鲜度文案；维持 380×680 外框和内容滚动边界。
8. 实现手动反馈关闭语义：已完成提示关闭即清，运行中操作不取消，但若期间关闭则终态不跨重开显示；增加成功、失败及关闭竞态模型测试。
9. 修改“关于”页为指定两行文案，以 `Link` 仅包裹“季悠然”并打开指定 HTTPS URL；增加结构或 action 回归测试。
10. 更新/替换 SettingsWindowActionTests、DashboardLayoutTests 和 UI tests：真实左键开关、右键不打开浮窗、动态菜单、设置窗口；明暗模式检查新标题布局、长诊断菜单和 380×680 尺寸。
11. 运行全量测试、独立状态栏 UI 测试和 Release 构建；执行 `git diff --check`。随后运行 `trellis-check`，根据结果修复并重跑。
12. 用 `trellis-update-spec` 同步 macOS 项目形态、SwiftUI 状态栏/生命周期、测试和新鲜度展示契约；最终提交并按 Trellis 流程归档。

## 验证命令

```sh
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-popover-menu-test
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-popover-menu-ui-test -only-testing:TokChanUITests/TokChanUITests
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-popover-menu-release build
git diff --check
```

## 高风险文件与验证对应

- `TokChan/TokChanApp.swift`：应用级模型与状态栏所有权，macOS 13 Settings scene，UI-testing 注入。
- 新增状态栏 coordinator 文件：鼠标事件、popover/menu 生命周期、可访问性及强引用。
- `TokChan/Features/Dashboard/DashboardView.swift`：footer 删除、标题新鲜度、固定布局。
- `TokChan/Features/Dashboard/DashboardViewModel.swift`：关闭时反馈清理与运行中完成竞态，不得改变请求/提交结果。
- `TokChan/Features/Settings/SettingsView.swift`：精确文案、链接行为。
- `TokChanUITests/TokChanUITests.swift`：SystemUIServer 暴露差异、左右键真实行为和 Settings 窗口。

## 回滚点

先完成纯 formatter/menu/operation 测试，再替换状态栏场景。若 `NSPopover` 在 macOS 13 出现已验证的焦点或布局阻断，可回滚 AppKit composition 并重新评估 `NSPanel`；不得用未公开的 MenuBarExtra 事件截获作为快捷修复。所有变更不迁移缓存、不修改远端数据，恢复原 `MenuBarExtra(.window)` 与 footer 即可回滚展示层。

## 实施结果（2026-09-06）

- 已以单一 `NSStatusItem` + transient `NSPopover` + 动态 `NSMenu` 替换 `MenuBarExtra(.window)`，共享应用级模型并保持 macOS 13 编译目标。
- 浮窗标题与右键菜单共用统计快照新鲜度 formatter；服务端日期固定按 Gregorian 年月日并使用用户本地时区比较。底部操作栏与资料 `updatedAt` 文案已移除。
- 右键菜单按当前状态展示更新时间、诊断、设置和退出，并通过临时 `statusItem.menu` + `performClick` 以原生状态栏菜单展示；左键继续切换 380×680 浮窗，popover delegate 独占可见性生命周期。
- 已覆盖已完成成功/失败及进行中成功/失败的关闭竞态；关闭不取消操作，终态横幅不跨重开遗留。关于页指定两行文案和作者链接已接入。
- `trellis-check` 的 Gregorian 日期问题已修复；Settings 优先调用 SwiftUI Command-Comma 命令并保留 responder fallback，相关操作竞态测试已补强。
- 最终全量验证：132 个单元测试、Release 构建与 Xcode Analyze 通过；2 个状态栏 UI 测试因当前 SystemUIServer 未暴露状态项而明确跳过，非功能失败。
- 用户使用本地 Release 构建手动验收了左/右键、原生状态栏菜单定位与高亮、设置打开及整体交互，确认通过。macOS 13 universal 编译目标和 `git diff --check` 均通过。
- 已同步 macOS index、SwiftUI、testing 与 Tokscale Settings 契约规范。

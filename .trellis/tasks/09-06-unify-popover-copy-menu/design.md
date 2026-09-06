# 状态栏菜单与浮窗交互设计

状态：已实施并通过自动化与用户手动验收。需求依据 `prd.md` R1–R5；平台调研及验收修正依据 `research/status-item-context-menu.md`。

## 架构与所有权

用一个应用级 AppKit 桥接替换当前 `MenuBarExtra(.window)`：

- `NSApplicationDelegate` 在 `applicationDidFinishLaunching` 中创建并长期持有唯一的 `NSStatusItemCoordinator`。
- 应用委托同时持有现有 Dashboard、开机启动和自定义价格模型；SwiftUI `Settings` scene 与状态栏浮窗继续复用同一组模型，禁止创建第二个 DashboardViewModel。
- coordinator 长期持有一个 `NSStatusItem`、一个 `.transient` 的 `NSPopover` 和一个承载 `DashboardView` 的 `NSHostingController`。
- 左键通过 `NSStatusBarButton.sendAction(on: [.leftMouseUp, .rightMouseUp])` 路由为浮窗显示/关闭；右键先关闭已显示浮窗，再临时将动态 `NSMenu` 赋给 `statusItem.menu` 并调用按钮 `performClick`，由 AppKit 以原生状态栏菜单方式定位和高亮。
- 菜单跟踪结束后立即清空 `statusItem.menu`，避免接管后续左键；不使用 cursor-anchored context menu、不拦截 SwiftUI 私有窗口或使用全局事件监听。

保留 SwiftUI `Settings` scene 作为设置窗口所有者。右键菜单的“设置”统一调用可注入的 settings action：先激活应用并执行主菜单标准 Command-Comma Settings 命令，若不可用再依次发送 `showSettingsWindow:` / `showPreferencesWindow:`，继续兼容 macOS 13。退出 action 保持 `NSApplication.terminate`，测试中以注入 closure 替代真实退出。

## 左键浮窗与生命周期

popover 固定承载 380×680 的现有 DashboardView，锚定状态栏按钮，重复左键只切换同一实例；点击外部由 transient behavior 关闭。右键菜单出现前显式关闭 popover，避免菜单和浮窗重叠。

面板可见性只由 coordinator 的 `NSPopoverDelegate.popoverDidShow` / `popoverDidClose` 通知 DashboardViewModel；移除 DashboardView 的 `.onAppear` / `.onDisappear` 生命周期调用，避免一次显示触发两套计数或刷新调度。模型方法保持幂等，关闭只停止后续定时刷新，不取消已经开始且有时间上限的请求或手动提交。

保留 `dashboard-panel` 可访问标识和 DEBUG 生命周期计数，使现有真实状态栏开关 UI 测试可以迁移后继续验证。

## 统一数据新鲜度

提取一个纯展示 formatter/value，输入：

- 最近一次完整统计快照成功获取时间 `cacheSavedAt`；
- 当前选中范围服务端 `dateRange.end`；
- 用于比较的当前日期和 locale/timezone。

输出唯一口径：正常时为“更新于 …”；当服务端数据结束日期与今天不同，输出“数据日期 YYYY-MM-DD · 更新于 …”。该值同时用于浮窗标题区和右键菜单，避免两处各自格式化后漂移。

浮窗头像标题区不再显示 `profile.updatedAt`：保留用户显示名和 `@username`，在标题区以低对比 caption 显示统一新鲜度。无成功快照时不伪造时间，右键菜单可省略该信息项；浮窗仍依照现有首次加载/失败态表达无数据。

## 动态右键菜单

每次右键打开前从共享 MainActor DashboardViewModel 重建短菜单：

1. 若存在新鲜度文案，显示一个不可执行的信息项；
2. 若存在 `diagnosticMessages`，显示“刷新详情”子菜单，诊断内容作为不可执行项目，保留完整文本；无诊断时省略该入口；
3. 分隔线；
4. “设置…”；
5. “退出 TokChan”。

菜单描述生成与 AppKit 呈现分离：纯菜单 descriptor 可做单元测试，coordinator 只负责转成 `NSMenuItem` 及执行注入 action。动态读取发生在打开菜单时，禁止捕获启动时快照。

## 手动反馈生命周期

每次显式 Dashboard 操作开始时记录操作标识和当时的面板展示 generation。操作完成发布成功/失败前检查：

- 如果发起时面板不可见；或
- 操作期间该面板发生过关闭；或
- 完成时面板不可见，

则保留操作本身的执行结果与后续数据更新，但把 Dashboard 横幅状态收敛为 `.idle`。因此关闭时已完成的结果立即清除；关闭时仍运行的操作不会被取消，其稍后完成结果也不会在重开后遗留。若面板从发起到完成始终打开，横幅继续显示到本次面板关闭。

该机制只影响 Dashboard operation banner，不清除 `diagnosticMessages`，也不改变统计刷新、缓存或 CLI 语义。

## 关于页

保留 logo、标题和版本。将现有介绍替换为两行组合：

- `Tokscale的状态栏预览应用`
- `Made with love by 季悠然`

第二行仅“季悠然”使用 SwiftUI `Link` 指向 `https://blog.mitsuha.space`，由系统默认浏览器打开；保持系统链接样式、键盘访问和 accessibility。

## 兼容性、验证与回滚

- 最低 macOS 13；只使用公开 AppKit/SwiftUI API，不引入依赖。
- 视觉风险是 `NSPopover` 与 SwiftUI window-style MenuBarExtra 在箭头、阴影和焦点上的细微差异；以明暗外观和真实状态栏交互检查为准。
- 自动化覆盖纯点击路由、动态菜单内容、统一日期文案、操作关闭竞态、左键关闭/重开、右键菜单与 Settings。UI 环境不暴露 SystemUIServer status item 时保留明确 skip，并独立运行真实 UI 用例。
- 回滚可恢复 `MenuBarExtra(.window)` 和原 footer；不涉及缓存格式、用户配置、远端数据或迁移。

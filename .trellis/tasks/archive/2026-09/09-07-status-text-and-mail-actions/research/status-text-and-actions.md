# 状态栏文案与即时操作代码调研

## 现有边界

- `TokChan/Shared/StatusItemCoordinator.swift`：应用使用唯一 `NSStatusItem`、`NSPopover` 和动态 `NSMenu`。状态项当前为 `squareLength`，按钮只配置模板图标；菜单描述与 AppKit 呈现已分离。
- `TokChan/TokChanApp.swift`：应用委托持有唯一 `DashboardViewModel` 与 coordinator，设置窗口和状态栏共享该模型。
- `TokChan/Features/Settings/SettingsView.swift`：常规设置使用本地 `@State` 编辑，点击统一“保存”后调用 `DashboardViewModel.saveSettings`；适合将状态栏配置并入 `UserPreferences`。
- `TokChan/Shared/Services/PreferencesStore.swift`：小型偏好使用 `UserDefaults`；新增键可通过缺失键回退完成向后兼容。
- `TokChan/Features/Dashboard/DashboardViewModel.swift`：完整批次缓存在 `cachedProfiles`；`profileState` 和 `preferences` 已发布。`refresh()` 是 submit 后拉取，`retryStatistics()` 是只拉取，新增推拉分离入口应复用底层边界而不是错误复用组合操作。
- `TokChan/Shared/Models/TokscaleModels.swift`：`ProfilePeriod` 为 all/day/week/month，`DashboardData` 包含 totalTokens/totalCost。
- `TokChan/Shared/Utilities/DisplayFormatters.swift`：已有 compactNumber 与 currency，可直接定义 `{token}` / `{cost}` 输出。

## 既有契约

- `.trellis/spec/macos/swiftui-guidelines.md` 要求状态项由唯一 coordinator 管理，右键菜单每次从当前状态动态重建，并临时赋给 `statusItem.menu`。
- `.trellis/spec/macos/data-persistence.md` 要求 all/day/week/month 整批发布，失败保留旧数据，范围切换不独立请求。
- `.trellis/spec/macos/tokscale-integration.md` 定义 submit 与批量 fetch 的服务边界；静默读取不得执行 submit。
- `.trellis/spec/macos/state-management.md` 禁止把可计算展示字符串存为独立可变状态。

## 设计结论

1. 新配置并入 `UserPreferences`：默认关闭、默认模板 `{token} · {cost}`、默认 `.day`；范围以 raw value 保存，未知值回退 `.day`。
2. 提取纯模板渲染器，只做两个字面替换；未知变量、普通文本和空模板原样保留。
3. ViewModel 暴露只读的状态栏展示计算结果/对应范围读取，不建立新请求。Coordinator 观察已发布的 preferences/profileState 变化并更新按钮；开启且有非空结果时使用 variable length，否则回到 square length。
4. 菜单加入两个可禁用 action descriptor，顺序为信息/诊断、分隔线、推送、拉取、分隔线、设置、退出。
5. 新增 push-only 与 pull-only ViewModel 方法。成功不产生额外外部提示；push 失败增加轻量诊断，pull 失败复用统计读取诊断。任一 operation 运行时两个菜单项均禁用。

## 测试重点

- 模板重复变量、未知变量、纯文本、空模板、零值与格式化。
- UserDefaults 新键 round-trip、缺失键和无效 period 回退。
- 无缓存/旧缓存/批次更新/配置切换对应的状态栏展示。
- 菜单顺序、启用状态及推拉命令隔离：push 无 fetch，pull 无 submit。
- 原生状态栏 variable/square length、左右键和动态菜单手动或 UI 验证。

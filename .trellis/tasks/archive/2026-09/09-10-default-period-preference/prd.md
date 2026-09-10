# 新增默认时间粒度配置项

## Goal

在设置中提供「默认时间范围」配置项，默认值为「日」，可选范围沿用当前已支持的全部时间粒度（全部 / 日 / 周 / 月）。该配置决定**每次打开菜单栏面板**时默认选中的时间范围，取代现在硬编码的「全部」，并覆盖用户上一次会话的手动切换。

## Background

### 现状事实（代码勘查结论）

- 时间粒度唯一集合：`TokChan/Shared/Models/TokscaleModels.swift:3` `enum ProfilePeriod: String, Codable, CaseIterable, Identifiable { case all, day, week, month }`，标题为「全部 / 日 / 周 / 月」。
- 面板时间范围：`TokChan/Features/Dashboard/DashboardViewModel.swift:69` `selectedPeriod` 硬编码初值 `.all`；UI 在 `TokChan/Features/Dashboard/DashboardView.swift:39-49`（`period-picker`），取值 `ProfilePeriod.allCases`，`.pickerStyle(.segmented)`。
- 面板选择被缓存快照持久化：`TokChan/Shared/Services/DashboardCacheStore.swift:32` `selectedPeriod`，加载时 `DashboardViewModel.swift:243` 恢复，解码回退 `?? .all`（`DashboardCacheStore.swift:117`）。该字段属于既有 schema 契约（`.trellis/spec/macos/data-persistence.md` 「Dashboard snapshot cache」）。
- 面板打开钩子是现成的且无副作用：`DashboardViewModel.swift:303` `panelDidAppear()` 由 `TokChan/Shared/StatusItemCoordinator.swift:277` 的 `popoverDidShow` 调用，只做可见性标记。
- 面板打开**不得**启动/停止/加速刷新调度（`.trellis/spec/macos/data-persistence.md` 明确契约）；完整批次成功时四个粒度都在内存缓存中（`DashboardViewModel.swift:1207` `cacheIsComplete`）。
- 重置配置：`DashboardViewModel.swift:831` `selectedPeriod = .all`（硬编码）。
- 状态栏文案有独立的「统计范围」`UserPreferences.statusTextPeriod`（`PreferencesStore.swift:19`、`SettingsView.swift:282-288`），默认已是 `.day`（`PreferencesStore.swift:34`、`115-116`）。
- 设置页 Tab：常规 / 展示配置 / 自动提交 / 自定义价格 / 关于（`SettingsView.swift:107-137`）；展示配置页现有「模型明细」「客户端」两个 Section（`SettingsView.swift:333-382`）。
- 偏好落盘模式：`UserDefaultsPreferencesStore`（`PreferencesStore.swift:76-140`）+ `DashboardViewModel.updatePreferences(_:)`（`DashboardViewModel.swift:720`）即时保存，无保存按钮。

## Decisions

- **D1 作用范围**：仅 Dashboard 面板时间范围。新增独立偏好 `UserPreferences.defaultPeriod`（默认 `.day`）决定面板打开时默认选中的粒度；状态栏文案的「统计范围」`statusTextPeriod` 保持现状独立，**不联动、不迁移**。
- **D2 生效语义**：**每次打开面板都强制回到配置粒度**。在面板可见之前应用用户配置值（`panelWillAppear()`，由 `StatusItemCoordinator` 在 `NSPopover.show` 之前调用），包括抹掉本次运行内用户刚手动切过的选择；`panelDidAppear()` 在面板出现后重复同一次应用（幂等），保留原可见性与计数语义。用户仍可在面板内随时切换，只是下次打开面板会回到配置值。
- **D3 设置位置与命名**：设置 → 展示配置，新增「时间范围」分区（置于「模型明细」之前），Picker 标签「默认时间范围」，下拉选择样式（`.pickerStyle(.menu)`，取代原分段 tab 样式），选项为 `ProfilePeriod.allCases`。

## Requirements

- **R1 偏好持久化**：`UserPreferences` 新增 `defaultPeriod: ProfilePeriod`（init 默认值 `.day`）；新增 UserDefaults key `defaultPeriod` 并加入 `Key.all`（`clear()` 覆盖）；load 时缺失 key 或未知 raw value 回退 `.day`；save 写入 rawValue；`DashboardViewModel.normalized(_:)`（`DashboardViewModel.swift:1329`）透传该字段。
- **R2 设置 UI**：展示配置页新增 `Section("时间范围")`，Picker 标签「默认时间范围」、`.pickerStyle(.menu)`（下拉选择，不用分段 tab）、`ForEach(ProfilePeriod.allCases)`、`.accessibilityIdentifier("default-period")`，并配一行说明文案（打开面板时回到该范围）。走 `preferenceBinding(\UserPreferences.defaultPeriod)` 即时保存，无保存按钮。
- **R3 打开面板强制重置（且不得闪烁）**：`StatusItemCoordinator` 在 `NSPopover.show` **之前**调用 `panelWillAppear()`，把 `selectedPeriod` 设为 `preferences.defaultPeriod`；`panelDidAppear()` 在面板出现后重复同一幂等应用。重置必须在同一 MainActor 回合内同步更新展示数据（`profileState` / `identityProfile`），使首帧直接就是配置粒度，绝不出现「先渲染快照恢复的旧粒度、再跳到配置值」的闪烁。
- **R4 重置不产生外部副作用**：面板打开引发的粒度重置只消费内存批次，**不得**发起 Tokscale CLI/API 调用，不得写缓存，不得启动/停止/加速刷新调度。若目标粒度不在内存批次中，进入加载态等待应用级调度发布，而不是发起独立请求。
- **R5 重置配置行为**：`resetConfiguration` 后 `selectedPeriod` 落在配置默认值（清除后的 `UserPreferences.defaults` → `.day`），不再是硬编码 `.all`。
- **R6 文档与发布片段**：README 说明该设置项与「打开面板回到默认范围」的行为；新增 `release-notes/fragments/` 片段（现有片段格式：`{"category": "新增", "summary": "..."}`）。

## Acceptance Criteria

- [x] **AC1** 全新安装（无任何偏好 key）打开设置 → 展示配置，默认时间范围下拉选择器显示「日」；打开面板时 `selectedPeriod == .day` 且展示的指标与日期范围属于 `.day`。
  - 证据：`PreferencesStoreTests` 断言缺失 key / 未知 raw value 解码为 `.day`；`DashboardDataModeTests` 断言默认 `.day`；面板打开路径由下方 `.week` 变体测试覆盖（同一条 `applyCachedPeriod` 代码路径）。人工：设置页默认显示「日」。
- [x] **AC2** 把默认改为「周」，即使上一次会话手动切到过「全部」，关闭再打开面板后选择器与展示数据都落在「周」。
  - 证据：`DashboardViewModelTests.testPanelOpenAppliesConfiguredDefaultPeriodFromMemoryBatchWithoutSideEffects`（快照 `.all` + 偏好 `.week` → `selectedPeriod` / `profileState` / `identityProfile` 同为 `.week`）。人工：面板验证通过。
- [x] **AC3** 面板打开期间手动切到「月」，关闭后重新打开 → 回到配置值。
  - 证据：`DashboardViewModelTests.testPanelReopenDiscardsManualPeriodSwitchInFavorOfPreference`。
- [x] **AC4** 面板打开引发的粒度重置记录 **0** 次 `submit` / `run` / `fetch` / `configure` / `disable` 事件，且缓存快照写入次数为 0。
  - 证据：`testPanelOpenApplies…`、`testPanelOpenOnStaleCacheNeverSpawnsAnAutomaticReload`（陈旧快照 + 排空 main-actor 队列）、`testPanelOpenWithoutConfiguredPeriodInBatchShowsLoadingAndRecordsNoEvents` 均断言 `events.isEmpty` 且 `cache.saveCount` 不变。
- [x] **AC5** 老版本升级（UserDefaults 无 `defaultPeriod` key）不崩溃、不报错，默认值解析为 `.day`；`clear()` 会移除该 key。
  - 证据：`PreferencesStoreTests` 缺失 key / 未知 raw value 回退 `.day`，且 `defaultPeriod` 已加入 `Key.all`（`clear()` 断言集合）。
- [x] **AC6** 重置配置后 `selectedPeriod == .day`，且重新打开面板仍为「日」。
  - 证据：`DashboardDataModeTests` 重置后断言 `.day`；`resetConfiguration` 改为读取 `preferences.defaultPeriod`。
- [x] **AC7** `PreferencesStoreTests` 覆盖新字段的非默认值往返、缺失 key 回退 `.day`、未知 raw value 回退 `.day`；既有 `DashboardCacheSnapshot.selectedPeriod` 往返测试保持通过（schema 不变）。
  - 证据：全量 `TokChanTests` 283 tests / 0 failures，含 `DashboardCacheStoreTests`。
- [x] **AC8** 展示配置页 UI 测试断言 `default-period` 是下拉选择控件（`popUpButtons`）且可切换并即时持久化，既有 `settings-display-page` / 模型明细 / 客户端断言不回归。
  - 证据：**仅人工验证**（设置页下拉可选「日/周/月/全部」并即时持久化，用户确认）。自动化方面 UI 测试已改写为 `application.popUpButtons["default-period"]` + `menuItems` 选择，但本机 SystemUIServer 不暴露状态栏项，4 项 UI 测试全部 skip → 无自动化证据，待 CI 或隔离环境运行。
- [x] **AC9** 面板首帧即为配置粒度：当快照恢复的旧粒度与配置值不一致时，打开面板不出现旧粒度闪现（`panelWillAppear()` 于 `NSPopover.show` 之前完成应用，且不增加 `panelAppearanceCount`）。
  - 证据：`testPanelWillAppearAppliesConfiguredPeriodBeforeThePanelIsCountedAsVisible`（单次 `panelWillAppear()` 即落 `.week`、计数不变、零事件零写盘；随后 `panelDidAppear()` 幂等）。人工：连续开关面板不再出现「日 → 周」闪烁。

## Out of Scope

- 不改动状态栏文案的 `statusTextPeriod`（独立、不联动、不迁移）。
- 不新增或修改 `ProfilePeriod` 的取值集合。
- 不修改 `DashboardCacheSnapshot` schema；`selectedPeriod` 字段保留原有往返语义。
- 不改变后台刷新调度、300 秒 TTL、自动失败退避、模式（本地/在线）切换逻辑。
- 不做本地化（`Localizable.xcstrings`）与新增语言。

## Open Questions

（无阻塞项）

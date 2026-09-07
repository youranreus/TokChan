# 修复浮窗外侧点击不关闭

## Goal

恢复状态栏统计浮窗的原生临时浮窗语义：用户左键打开浮窗后，点击浮窗和状态栏按钮之外的区域应自动关闭，避免浮窗持续遮挡其他内容。

## Background and Confirmed Facts

- 浮窗由 `TokChan/Shared/StatusItemCoordinator.swift` 中唯一的 `NSPopover` 承载，当前已设置 `behavior = .transient`；按 AppKit 语义，临时浮窗应在用户与其他界面交互时关闭。
- 该行为曾作为归档任务 `09-07-settings-interaction-popover-style` 的明确回归约束和人工验收项，当前再次复现。
- 排查确认：`NSApplication.activate` 对 `LSUIElement` 应用仍然必要，但激活应用并不保证状态栏锚定的 popover window 成为 key window；当前打开路径缺少 `show` 后的显式 `makeKey()`，导致 AppKit 可能未建立完整的 `.transient` 外侧关闭生命周期。
- 状态栏左键仍应切换浮窗，右键仍应先关闭浮窗再展示菜单；关闭回调仍负责通知 `DashboardViewModel.panelDidDisappear()`。

## Requirements

| ID | Requirement |
| --- | --- |
| R1 | 左键打开统计浮窗后，点击浮窗与状态栏按钮之外的其他应用或桌面区域时，浮窗自动关闭。 |
| R2 | 保持状态栏左键打开/再次点击关闭、右键菜单、设置窗口、浮窗尺寸与系统外观等既有行为不变。 |
| R3 | 保留显示前激活应用，并在 `show` 创建 popover window 后显式将其设为 key window，以恢复原生 `.transient` 外侧关闭；不以全局事件监听器掩盖原生行为问题。 |
| R4 | 为可抽离的浮窗开关决策补充回归测试，并保留真实 `NSPopover` 的手动验收，因为单元测试不能完整模拟系统级外侧点击。 |

## Acceptance Criteria

- [x] AC1（R1）：从菜单栏左键打开浮窗，分别点击桌面和另一个应用窗口，浮窗均自动关闭。
- [x] AC2（R2）：再次点击 TokChan 状态栏图标可关闭已打开浮窗；右键仍展示状态菜单，且不会遗留浮窗。
- [x] AC3（R2）：关闭后 `popoverDidClose` 生命周期仍发生，再次打开不显示上一轮已经结束的操作横幅。
- [x] AC4（R3、R4）：聚焦单元测试覆盖浮窗显示/关闭操作顺序，相关全量单元测试、Release 构建和 `git diff --check` 通过。

## Out of Scope

- 自绘浮窗、箭头、阴影或圆角。
- 新增全局/局部鼠标事件监听器，除非原生 `.transient` 行为经证据证明无法满足需求。
- 修改 Dashboard 内容、首次引导、缓存刷新或设置业务逻辑。

## Risks and Deferred Items

- XCTest 的闭包级单元测试只能保护操作顺序，无法证明 macOS 对真实 `NSPopover` 的系统级 outside-click 行为；最终需在本机对桌面与其他应用两种点击目标做手动验收。
- 当前根因是基于提交历史和当前实现得出的高可信候选，实施阶段仍应先用最小实验验证，避免把相关性当作结论。

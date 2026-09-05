# 设置页面横向 Tab 布局

## Goal

将 TokChan 设置窗口改造成接近 Safari 设置的顶部横向 Tab 布局，让配置项按用途分组，减少页面自绘的窗口操作控件，并提供一个清晰的「关于」页。

## Background

当前 `SettingsView` 在单一 `Form` 中同时展示所有配置，并自行绘制标题、关闭按钮、取消按钮和保存按钮。应用入口已经使用 SwiftUI 原生 `Settings` 场景，窗口关闭应由 macOS 窗口控制。

## Requirements

- 设置窗口顶部居中显示标题「TokChan! 设置」。
- 标题下方提供居中排列的横向 Tab，至少包含「常规」「自动提交」「关于」，其中「关于」必须是最后一个 Tab。
- 「常规」Tab 展示 Tokscale 用户名、Tokscale 版本和 npx 可执行文件路径配置。
- 「自动提交」Tab 展示现有自动提交开关、间隔、客户端、提交范围和日期筛选配置。
- 「关于」Tab 展示基础应用信息，包括应用名称、当前应用版本和 TokChan 的用途说明。
- 移除设置页自绘的关闭按钮，使用窗口自带的关闭操作。
- 保留现有设置保存行为，保存仍应一次性提交常规设置和自动提交设置；保存成功后关闭窗口。
- 保留现有错误提示、加载中禁用保存和 npx 文件选择行为。

## Acceptance Criteria

- [x] 设置窗口标题区域显示「TokChan! 设置」，标题居中。
- [x] Tab 位于原生 Preferences Toolbar，Tab 顺序中「关于」为最后一项。
- [x] 切换 Tab 时只有对应配置内容可见，且切换不会丢失当前未保存的输入值。
- [x] 常规与自动提交配置均可编辑，现有 npx 选择和保存流程继续工作。
- [x] 关于页显示应用名、版本号和用途等基础信息。
- [x] 页面不再渲染自绘关闭按钮；窗口仍可通过 macOS 标准窗口控件关闭。
- [x] 现有测试通过，项目可通过 macOS Xcode build/test 验证。

## Out of Scope

- 不改变偏好设置的存储格式、Tokscale CLI 调用或自动提交业务逻辑。
- 不增加设置项、账号管理、更新检查或外部链接功能。
- 不重做菜单栏 Dashboard 或应用整体视觉主题。

## Technical Notes

- 继续使用 SwiftUI `Settings` scene 和现有 `DashboardViewModel`。
- 使用本地 `@State` 保存跨 Tab 编辑中的草稿状态；用类型化枚举表达 Tab 选择。
- 版本号从应用 bundle 的 `CFBundleShortVersionString` 读取，读取不到时提供稳定的回退文本。

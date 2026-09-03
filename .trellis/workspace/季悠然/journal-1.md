# Journal - 季悠然 (Part 1)

> AI development session journal
> Started: 2026-09-03

---

## 2026-09-03 Tokscale menu bar app
- 完成 macOS 13+ SwiftUI 状态栏应用、Tokscale API/CLI 集成、autosubmit 管理、缓存、设置窗口和测试。
- 修复设置按钮无法打开窗口：macOS 14+ 使用 `SettingsLink` 对接 SwiftUI `Settings` scene，macOS 13 保留 `showSettingsWindow:` 兼容路径。
- 修复公开资料用户名 path segment 编码，避免 `/`、`?`、`#` 改变请求语义。
- 验证：`xcodebuild ... build`、`xcodebuild ... test`、`git diff --check` 均通过；用户已验收设置窗口修复。
- 工作提交：`f66f284 feat: build Tokscale menu bar app`；归档提交：`49d3ba2 chore(task): archive 09-03-tokscale-menubar-app`。

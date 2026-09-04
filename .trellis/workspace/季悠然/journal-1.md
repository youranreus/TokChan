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


## Session 1: 更新 TokChan 品牌图标

**Date**: 2026-09-03
**Task**: 更新 TokChan 品牌图标
**Branch**: `master`

### Summary

使用仓库内原始品牌素材生成并接入 macOS AppIcon、菜单栏 Template Image 和关于页透明 Logo；完成构建、26 个单元测试及 1 个 UI 测试验证。

### Git Commits

| Hash | Message |
|------|---------|
| `145b000` | (see git log) |

### Status

[OK] **Completed**


## Session 2: Dashboard usage periods and persistent cache

**Date**: 2026-09-04
**Task**: Dashboard usage periods and persistent cache
**Branch**: `master`

### Summary

用户验收通过。完成浮层布局、客户端图标和 Tokens 比例条，按 Tokscale 数据提供日周月展示；持久化各粒度缓存，统一提交与加载按钮，修复切换及异步发现竞态。

### Main Changes

- 实现 cache-first JSON 缓存与粒度选择持久化；每日数据使用上游日贡献记录。
- 31 个客户端图标随包分发；自动提交状态迁入设置。

### Git Commits

| Hash | Message |
|------|---------|
| `c12c275` | (see git log) |

### Testing

- [OK] 41 项单元测试全量通过，随后新增的选择持久化回归及 DashboardViewModelTests 定向通过。
- [OK] Release 构建和 codesign 校验通过；最终 SwiftUI 明暗截图检查通过。原生交互检查受 CUA 超时限制。

### Status

[OK] **Completed**

### Next Steps

- 最新构建位于 /private/tmp/TokChan-cache-first-release/Build/Products/Release/TokChan.app。


## Session 3: 实现构建与发布流程

**Date**: 2026-09-04
**Task**: 实现构建与发布流程
**Branch**: `master`

### Summary

完成 TokChan 本地 universal ZIP 构建、patch 版本与 annotated Tag 脚本、Tag 驱动的 GitHub draft Release 工作流、脚本测试、README 与发布契约；本地单元测试、双架构 Release 构建、ZIP 和 SHA-256 校验通过。

### Git Commits

| Hash | Message |
|------|---------|
| `03e7752` | (see git log) |
| `00407bb` | (see git log) |

### Status

[OK] **Completed**


## Session 4: 优化发布脚本版本更新

**Date**: 2026-09-04
**Task**: 优化发布脚本版本更新
**Branch**: `master`

### Summary

发布脚本新增 patch、minor、major 语义化版本递增，移除本地 gh 依赖并保留 CI 的 GitHub Release API 发布职责；同步更新测试、README 与发布规范，22 项脚本检查通过。

### Git Commits

| Hash | Message |
|------|---------|
| `4f65b27` | (see git log) |

### Status

[OK] **Completed**


## Session 5: 自动探测 npx 路径

**Date**: 2026-09-04
**Task**: 自动探测 npx 路径
**Branch**: `master`

### Summary

让设置页默认展示自动探测到的 npx，手动覆盖按需展开并支持无效路径回退与清除；补充定位器及设置状态测试，完整 Xcode 测试通过。

### Git Commits

| Hash | Message |
|------|---------|
| `7c917b1` | (see git log) |

### Status

[OK] **Completed**


## Session 6: 兼容常见 Node 版本管理器探测

**Date**: 2026-09-04
**Task**: 兼容常见 Node 版本管理器探测
**Branch**: `master`

### Summary

扩展 NpxLocator，支持 fnm、Volta、asdf、mise、nodenv、n 与 nvm 的安全文件系统探测，保留确定性优先级并排除不安全 shim；补充完整路径、安全和回退测试，随后发布 v0.1.6。

### Git Commits

| Hash | Message |
|------|---------|
| `dda32f7` | (see git log) |

### Status

[OK] **Completed**

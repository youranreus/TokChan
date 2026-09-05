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


## Session 7: 添加 macOS 开机自启动设置

**Date**: 2026-09-05
**Task**: 添加 macOS 开机自启动设置
**Branch**: `master`

### Summary

使用 SMAppService.mainApp 为 TokChan 增加符合 macOS 13 规范的登录时启动设置，系统状态作为唯一事实来源，覆盖待批准、错误恢复和外部状态刷新；补充测试与 Service Management 代码规范。

### Main Changes

- 新增可注入的 SMAppService 登录项服务与设置状态模型
- 在常规设置中加入立即生效的登录时启动开关及系统批准引导
- 增加 Service Management 规范、规划研究与 12 个聚焦测试

### Git Commits

| Hash | Message |
|------|---------|
| `eeaa585` | (see git log) |

### Testing

- [OK] xcodebuild test：77 个单元测试与 1 个 UI 测试通过
- [OK] Release universal macOS build 与 git diff --check 通过

### Status

[OK] **Completed**

### Next Steps

- 使用签名安装版手动验证系统登录项、批准流程与重启后启动


## Session 8: 修复发布包 ad-hoc Bundle 签名

**Date**: 2026-09-05
**Task**: 修复发布包 ad-hoc Bundle 签名
**Branch**: `master`

### Summary

定位 TokChan 0.1.7 发布包只有 linker-generated 签名、导致 SMAppService.mainApp 返回 notFound；发布流水线现对完整 App Bundle 执行 credential-free ad-hoc 签名，并在打包前及 ZIP 解压后严格复验。

### Main Changes

- 为完整 TokChan.app 添加确定性 ad-hoc 签名与签名元数据校验
- 增加 ZIP 解压后复验及签名失败的 fail-closed 发布保护
- 扩展发布 fixture、GitHub Release 警告、README 与 macOS 规范

### Git Commits

| Hash | Message |
|------|---------|
| `841e1aa` | (see git log) |

### Testing

- [OK] 发布脚本 fixture 32/32、版本测试 7/7 通过
- [OK] Xcode 77 个单元测试与 1 个 UI 测试通过
- [OK] 真实 universal Release ZIP 的 Bundle 签名、标识符、资源封装和校验和通过

### Status

[OK] **Completed**

### Next Steps

- 发布新的补丁版本，并用签名安装包手动验证 SMAppService 登录项

# 首次引导现状与外部入口证据

## Repository evidence

- `TokChan/Features/Dashboard/DashboardView.swift`：无资料时通过 `ErrorStateView` 调用 `retryStatistics()`；该动作只重拉统计。
- `TokChan/Features/Dashboard/DashboardViewModel.swift`：
  - `load()` 在用户名为空时尝试 `whoAmI`，随后执行完整批次读取；
  - `updatePreferences(_:)` 负责用户名规范化、持久化、旧账号缓存隔离和 generation 失效；
  - `refresh()` 已提供 `submit → forced complete batch fetch` 顺序，但反馈语义面向正常 Dashboard；
  - `reloadProfiles` 将空用户名、404 和其他读取失败都收敛为字符串失败，需要为引导保留 typed result。
- `TokChan/Shared/Services/TokscaleAPIClient.swift`：HTTP 404 映射为 `TokscaleAPIError.profileNotFound`；完整读取必须返回 all/day/week/month 同账号批次。
- `TokChan/Shared/Models/TokscaleModels.swift`：`DashboardData.totalTokens` 是 API `stats.totalTokens` 的直接映射；客户端明细可能稀疏或为空，因此不适合作为引导完成条件。
- `README.md`：运行提交/自动提交要求现有 Tokscale 登录；首次 panel 会在没有保存 override 时用 `whoami` 发现用户名。

## External evidence

- 2026-09-07 读取 `https://tokscale.ai` 首页，页面提供产品介绍、排行榜和 GitHub 入口，未暴露独立 signup/register 链接。
- Tokscale GitHub 文档描述账号流程为 `tokscale login` 发起 GitHub OAuth，并用 `tokscale whoami` 查询当前身份。
- 产品决策仍选择让“没有账号”按钮直接打开 `https://tokscale.ai`，不在本任务新增 CLI login 能力。

## Planning implications

- 引导必须复用现有偏好、完整批次和 CLI boundary，不能新增第二套账号或提交实现。
- 首次路径需区分 typed `profileNotFound` 与瞬时/协议错误；普通 Dashboard 刷新仍遵守旧数据保留和错误诊断合同。
- 完成条件集中定义为同账号完整批次的 all `totalTokens > 0`。

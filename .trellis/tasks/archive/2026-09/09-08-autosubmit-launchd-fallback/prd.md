# 实现 autosubmit launchd 兼容回退

## Goal

在 Tokscale 上游仍错误调用 `launchctl bootout --wait` 的期间，让 macOS 用户能够从 TokChan 成功重新应用自动提交设置并更新定时任务托管版本。

## Background

- TokChan 使用当前已保存的 `npx` 路径和 Tokscale 版本执行 `autosubmit enable`；成功后再读取一次状态。
- 本机已确认 Tokscale 4.15.1 在已有 LaunchAgent 时执行 `launchctl bootout --wait gui/<uid>/ai.tokscale.autosubmit`，macOS 返回退出码 64 和 `Unrecognized target specifier`。
- 不带 `--wait` 的 `launchctl bootout gui/<uid>/ai.tokscale.autosubmit` 在本机可正常卸载旧服务，但仅卸载服务仍不足：Tokscale 会因其持久化启用状态在重试时再次走错误 bootout。
- 本机已验证闭环恢复：正确 bootout 后，以同一 Tokscale 版本执行 `TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1 autosubmit disable`，再执行原始 enable，可成功重建 LaunchAgent，并将 managed version 更新为 4.15.1。
- 当前项目约定 TokChan 不直接管理 LaunchAgent；本任务是针对已确认上游缺陷的窄范围临时兼容例外。

## Requirements

- 首次仍正常调用当前设置版本的 `tokscale autosubmit enable`，不改变正常路径。
- 只有错误同时明确指向 `launchd bootout failed`、`launchctl bootout --wait`、退出状态 64 和 `Unrecognized target specifier` 时，才进入兼容回退。
- 回退使用系统 `/bin/launchctl`，仅卸载当前 GUI 用户域中的固定服务 `ai.tokscale.autosubmit`；参数必须以离散数组传递，不使用 shell。
- 成功卸载旧服务后，以相同 npx 路径和 Tokscale 版本执行一次官方 `autosubmit disable`，并仅为该子进程设置 `TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1`，由 Tokscale 自身清理持久化状态与托管副本。
- 状态清理成功后，仅重试一次原始 `autosubmit enable` 命令；禁止无限重试，且环境变量不得泄漏到重试。
- launchd 卸载、Tokscale 状态清理或重试任一步骤失败时，向用户返回真实错误，不得报告虚假成功。
- 重试成功后沿用现有流程读取一次 autosubmit 状态，以验证新配置与托管版本。
- 用户直接禁用 autosubmit、立即运行、普通提交以及其他 CLI 命令不启用该回退；带环境变量的 disable 仅可由精确命中的恢复流程内部调用。
- 补充单元测试覆盖正常成功、精确命中特定错误后的完整恢复、近似但不匹配错误不回退、两阶段清理失败、重试失败与环境隔离。

## Acceptance Criteria

- [x] 已加载旧 `ai.tokscale.autosubmit` LaunchAgent 时，在本机通过 TokChan 重新应用配置成功。
- [x] 调用顺序严格为 `enable → /bin/launchctl bootout gui/<uid>/ai.tokscale.autosubmit → TOKSCALE_AUTOSUBMIT_SKIP_SCHEDULER=1 autosubmit disable → enable → status`。
- [x] 新状态反映提交的配置，并显示当前设置 Tokscale 版本对应的 managed executable。
- [x] 非精确匹配错误只执行一次 `enable` 并原样失败。
- [x] 回退命令不含 `--wait`，不接受动态 service label，不通过 shell 执行。
- [x] launchd 卸载、状态清理与重试均有次数上限；环境覆盖仅作用于状态清理，任一步骤失败均可观察且不会误报成功。
- [x] 相关单元测试及完整 macOS 测试通过。

## Out of Scope

- 修改或发布 Tokscale 上游包。
- 直接编辑或删除 Tokscale 的 plist、settings JSON 或 managed executable。
- 为其他 launchd 错误提供通用恢复。
- 改变自动提交配置字段、界面布局或调度语义。

## Deferred Removal

- 上游 Tokscale 发布且项目最低可用版本包含正式修复后，应删除此兼容分支及其直接 `launchctl` 例外。

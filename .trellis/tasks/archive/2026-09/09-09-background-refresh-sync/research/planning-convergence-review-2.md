# 第二次规划收敛审查

日期：2026-09-09

## 结论

**READY**

当前 `prd.md`、`design.md`、`implement.md`、`implement.jsonl` 与 `check.jsonl` 已达到可决策、可实施状态。需求、设计机制和验证计划之间没有阻塞性断层，也没有仍需用户决定的 MVP 产品、范围、UX、兼容性、风险容忍或验收语义。

## 前次七项发现复核

| # | 前次发现 | 当前状态 | 证据 |
|---|---|---|---|
| 1 | AC5 与共享自动退避冲突 | 已解决 | `prd.md` AC5 明确 stale 且退避外至多一批、退避内零请求；与 R4 和 `design.md` Failure backoff 一致。 |
| 2 | 启动身份发现流程不足 | 已解决 | `design.md` Architecture 明确已有 username 立即评估；无 username 时仅一次 `whoami`，成功保存后立即重新评估，完成前 timer/wake no-op；`implement.md` 第 1–2 步要求对应测试。 |
| 3 | Settings 每次可见还是仅首次创建未决 | 已解决 | R8/AC9 与 `design.md` Ownership and Lifecycle 均规定每次不可见→可见查询一次，覆盖新建和重新前置，同一连续可见期合并；第 6 步要求测试。 |
| 4 | panel lifecycle review gate 与 R5 冲突 | 已解决 | `implement.md` Review Gates 明确 panel 生命周期完全不触发统计，只保留展示反馈职责。 |
| 5 | AC8 缺少明确实施/测试项 | 已解决 | `implement.md` 第 9 步明确 submit 失败零读取，以及 submit 成功/read 失败保留旧快照与 `fetchedAt` 并显示部分成功反馈。 |
| 6 | context manifests 缺项 | 已解决 | `implement.jsonl` 已含 networking、quality；`check.jsonl` 已含 state-management、networking、quality；两者各 9 条，`task.py validate` 通过。 |
| 7 | PRD 含机器瞬时状态 | 已解决 | 当前 Background 仅保留架构和行为事实，不再包含本机 autosubmit 开启状态或 20 分钟间隔。 |

## 需求到设计到验证映射

| 需求 | 设计机制 | 计划验证 |
|---|---|---|
| R1 | 单一 app-level deadline scheduler；以成功 `fetchedAt` 为 300 秒 TTL；完整批次发布后状态栏 Combine 更新 | AC1；步骤 2–5、9–10：panel 从未打开/已关闭的 deadline 批次、状态栏更新、scheduler 唯一性 |
| R2 | 自动入口仅进入统计 freshness gate；CLI mutation 只存在于显式用户操作或外部 Tokscale autosubmit | AC2；步骤 2、6 与 Review Gate：app start/deadline/panel/wake 的 CLI 事件零 submit/run/configure/disable |
| R3 | `DashboardViewModel` 保持唯一协调器；全部触发复用 `reloadProfiles(force:automatic:)`、完整批次、request ID/generation/account 隔离与旧数据保留 | AC3、AC4、AC6；步骤 2–4、7、9：合并、批次原子性、竞态、旧结果不可发布 |
| R4 | 启动立即评估；wake 薄入口；30/60/300 秒共享退避；成功复位；手动读取绕过；不补跑；回拨防 busy-loop | AC5、AC6；步骤 1、4–5：fresh/stale/backoff/wake/长睡眠/回拨确定性测试 |
| R5 | panel callbacks 仅管理可见性、banner generation 与反馈清理；scheduler 由应用生命周期拥有；允许 App Nap 延迟 | AC1、AC3；步骤 2–5、10：panel 开关不改变 scheduler/deadline，请求在关闭面板时仍能更新状态栏 |
| R6 | 三个显式动作收敛为 submit+forced refresh、read-only forced refresh、run+forced refresh/status；取消 push-only | AC4、AC7、AC8；步骤 7–9：操作路由、失败/部分成功、菜单 descriptor 与旧断言替换 |
| R7 | 可见文案/help/accessibility 明示上传边界；成功文案只说读取完成；统计时间只叫最近成功读取 | AC7、AC8、AC10；步骤 8–10：菜单/Dashboard/Settings 文案、380×680、无障碍、动态读取时间与反馈 |
| R8 | 独立 status-only 入口；严格事件表；Settings 可见期去重；context 变化失效并重查；统计 tick/wake/panel 不查状态 | AC9；步骤 6、9：所有正向事件、所有禁止事件、重新前置与连续可见去重 |
| R9 | status 独立 request ID/error/`autosubmitObservedAt`；统计独立 `fetchedAt`/错误；任一失败不回滚另一通道 | AC9、AC10；步骤 6、9 与 Review Gate：独立失败和独立时间戳推进 |
| R10 | submit/run 捕获 account、generation、CLI context；挂起期间上下文改变后旧操作 superseded，不发起后续新上下文读取或发布反馈 | AC4、AC11；步骤 7、9：账号、npx、版本在 suspend 期间变化的确定性竞态测试 |

AC11 要求的测试族均在步骤 1–10 中有对应落点；全量测试、Release 构建和 `trellis-check` 在步骤 11，规范迁移在步骤 12。`implement.jsonl` 与 `check.jsonl` 覆盖实施和复核所需的七份 macOS 规范及两份任务研究。

## 用户决策检查

已确认的用户所有产品决策：

- 菜单面板关闭时继续采用 5 分钟统计新鲜度窗口。
- autosubmit 状态按事件查询，不加入 5 分钟轮询。
- 取消 push-only，所有显式提交成功后刷新统计，同时保留明确的只读刷新。

剩余内容均为这些决定下的实现细节或验证方法，不需要再次询问用户。不存在 genuine user-owned MVP blocker。

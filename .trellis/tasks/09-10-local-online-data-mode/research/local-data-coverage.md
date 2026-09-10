# 本地 Tokscale 数据覆盖调研

调研日期：2026-09-10。当前仓库起始工作区干净；本次只创建任务与调研文档。

## 结论
Tokscale 4.15.1 的 graph JSON 能覆盖当前面板核心用量展示，无需自行解析各客户端日志。数据源切换涉及刷新、账号引导、缓存及异步请求隔离，不能只替换 API 调用。

## 本机验证
直接调用已安装的 4.15.1 二进制，避免 npx latest 安装或升级：
`~/.npm/_npx/450cf49d2ee863a8/node_modules/@tokscale/cli-darwin-arm64/bin/tokscale graph --no-spinner --output /tmp/tokchan-local-graph.json`
退出码 0。导出包含 118 个日桶、4 个客户端、60 个模型。未执行 submit 或修改自动提交配置。原始个人用量文件留在临时目录，不复制到仓库。
验证全部通过：summary.totalTokens 等于逐日 tokens 之和；summary.totalCost 与逐日成本之和浮点近似相等；每个日桶五类 Token 之和等于日总量；客户端 Token 之和等于日总量；所有客户端记录有 modelId。
限制：沙箱不允许写入 Tokscale source-message-cache-v2，且网络 DNS 不可用；本次代表缓存回退路径的字段验证，不代表正常网络下耗时基准或所有客户端兼容性验证。

## 字段覆盖
| 面板展示 | 本地来源 | 结论 |
| --- | --- | --- |
| 总 Tokens、成本 | summary.totalTokens / totalCost，或所选日期 contributions[].totals | 可覆盖 |
| Input/Output/Cache Read/Cache Write/Reasoning | contributions[].tokenBreakdown | 汇总可覆盖 |
| 客户端 Tokens、成本、占比 | contributions[].clients[].client/tokens/cost | 聚合可覆盖，占比分母使用同范围总量 |
| 模型明细 | clients[].modelId/tokens/cost | 按客户端及模型聚合可覆盖 |
| 全部、日、周、月 | 每日 contributions[].date | 可派生，时区与日期边界还需核对 |
| 日期范围及读取时间 | meta.dateRange/generatedAt + TokChan 完成读取时间 | 可覆盖，需区分最后用量日与刷新时间 |
| 活跃天数 | summary.activeDays | 实际可算，但按用户要求隐藏 |
| 排名、线上头像及用户名 | graph 不含公开账号资料 | 本地模式不应依赖这些字段 |
| 展示过滤及状态栏摘要 | 聚合后的同一批数据 | 可复用，但状态栏必须随数据源切换 |

## 现有代码落点
- TokChan/Features/Dashboard/DashboardView.swift:104：刷新图标调用 submitUsageAndRefreshStatistics，现有语义包含上传。
- 同文件 :122：四个指标包含排名、活跃天数；:68 账号头部依赖在线身份；:158 起空态文案指向已提交数据。
- TokChan/Shared/Models/TokscaleModels.swift:156 起 DashboardData 绑定 username 等身份字段；现有贡献记录解码已兼容 modelId，聚合可提取复用。实施前重新核对行号。
- TokChan/Features/Dashboard/DashboardViewModel.swift:770：读取入口要求非空用户名、调用公开 API，并以账号和 generation 防止过期结果写入。需加入数据源身份和独立缓存。
- TokChan/Shared/Services/DashboardCacheStore.swift:9：schema 2，完整快照强制要求 username 与四个范围；不能直接用于无账号本地快照。
- TokChan/Shared/StatusItemCoordinator.swift:366：菜单在线操作与面板目前共用方法，需要拆开语义。
- TokChan/Shared/Services/AppUpdater.swift：已有 AppUpdating/AppUpdater 及 canCheckForUpdates，可供菜单复用。
- TokChan/Shared/Services/PreferencesStore.swift：CLI 默认版本 latest；实际实施须明确最低兼容版本或导出能力检测。

## 网络与刷新边界
本机 graph 实际尝试请求 LiteLLM、models.dev、OpenRouter 价格以及 Cursor usage API，失败后使用缓存，最终成功导出。所以 graph 不等于完全离线读取。Cursor 数据来自同步到磁盘的缓存，不能保证每次都含最新线上用量。价格缓存缺失时成本可信度尚未验证。
`graph --help` 提供 --today、--week（最近七天）、--month（当前月）、--since/--until、--home；未提供显式 offline/no-sync 开关。不能将 --week 想当然当作自然周。
建议一次全量导出后派生四个范围，避免四次扫描及同步。要用上游实际时区合同确定今日与边界；不能拿最新用量日期当今天。

## 来源
- 官方文档 https://github.com/junhoyeo/tokscale/blob/main/README.md （列出 graph 导出能力）
- 固定版本源码 https://raw.githubusercontent.com/junhoyeo/tokscale/v4.15.1/crates/tokscale-cli/src/main.rs （Graph 命令参数与 Cursor 自动同步路径）
- 本机 4.15.1 graph --help 与真实导出结构，核心结论以上述实测为依据。
- 项目规范 .trellis/spec/macos/tokscale-integration.md、data-persistence.md；相关历史任务 09-09-background-refresh-sync、09-04-dashboard-usage-periods、09-07-first-use-onboarding。

## 待研究
用户已确认允许价格更新与 Cursor 同步，采用默认 graph 作为接入方向；验证首次无价格缓存、Cursor 缓存缺失、无账号和空数据路径；核对本地时区与线上周期差异；确定后台刷新成本、CLI 超时/取消与最低版本支持。

## 最终方案技术补充
- 固定版本 main.rs:5121–5205 确认 graph 无 --output 时只向 stdout 打印序列化 JSON，进度和警告走 stderr；产品使用 graph --no-spinner，无需固定临时输出文件。
- 同源码 :1785–1844 确认 today 使用 scanner pinned timezone，week 为包含今天的最近 7 天，month 为当月。现有线上合同见归档 research/tokscale-period-contract.md：week 为最近 7 天、month 为最近 30 天；本地须聚合 30 天而非调用 --month。
- 本机只读执行 4.15.1 config get timezone 成功，输出 Asia/Shanghai。作为本地日期计算输入，不能使用 meta.dateRange.end 推断当前日期。读取失败或无效时区按错误处理，避免静默错日。
- 当前 FoundationProcessRunner 已分离 stdout/stderr，并具备超时取消；TokscaleCLIClient 默认超时 300 秒，可复用。
- 当前偏好使用 UserDefaults.standard，bundle id 为 com.youranreus.TokChan；已确认真实 plist、Application Support 快照与 Caches 旧快照均存在，~/.tokchan 不存在。重置必须删除两处快照，防止 fallback 恢复。
- 登录时启动使用 SMAppService.mainApp，非普通 plist 开关；重置沿用服务调用并复查状态。Tokscale 共享配置不在清理所有权范围。
- 尚未覆盖的缺价/空数据组合与旧版 CLI 输出纳入实施测试；不作为已经验证的事实。未来上游 latest 改变输出会走明确不兼容错误，不自动调整用户配置。

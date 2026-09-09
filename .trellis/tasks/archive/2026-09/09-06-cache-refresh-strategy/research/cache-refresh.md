# 缓存与刷新调研

日期：2026-09-06。依据：当前仓库源码、已有任务及规范、公开一手文档。未执行真实提交操作或线上性能基准。

## 当前实现及问题
- TokChan/Shared/Services/DashboardCacheStore.swift:8：快照保存 profiles、selectedPeriod、autosubmit、savedAt；每范围还有 savedAt。:63 使用 Caches 目录，:85 原子写入。已有 JSON 方案足够，不需要数据库。
- TokChan/Features/Dashboard/DashboardViewModel.swift:111 起初始化恢复缓存；load() 对已有 profile/status 直接返回；selectPeriod() 对已有范围直接返回。缓存无 TTL 判断，因此可能永久陈旧。
- 同文件 refresh() 先 cli.submit 再 reloadProfile；reloadProfile 只读取 selectedPeriod，单范围更新并保存。runAutosubmitNow/saveSettings 同样仅更新当前范围。统一策略必须覆盖这些入口。
- reloadProfile 的 requestID 与 selectedPeriod 绑定；切换范围会使旧请求结果废弃。全组刷新应使用账号/批次 generation，选择只是展示状态。
- TokChan/Features/Dashboard/DashboardView.swift:57 用 .task 调 load；:89-104 按钮把读请求和提交统一视为 loading，帮助文案为提交本地用量并刷新当前范围；:116-135 有后台错误和操作成功 banner。需要区分用户主动操作与静默获取。
- TokChan/TokChanApp.swift:5 为 App 持有 StateObject，适合让刷新由模型管理；需验证 MenuBarExtra 关闭时 .task 取消及可见性回调，避免关闭导致全组刷新反复中断。
- TokChan/Shared/Services/TokscaleAPIClient.swift:76 将 day 映射 week，但单次接口返回映射后的 DashboardData。增加整组 API 读取能力可复用一个解码后的周响应，同时产生 day/week，另读 all/month，总计 3 次请求。
- TokChan/Shared/Models/TokscaleModels.swift:191-205 使用服务端 dateRange.end 投影今日。不得自行用本地时区重新汇总，跨日旧快照应标明实际日期。
- TokChanTests/DashboardViewModelTests.swift:56、:257 当前明确验证缓存不再请求及手动提交只 fetch 一次。此次属于有意行为变更，必须更新旧验收，而非保留旧断言后叠加后台请求。

## 既有决策
.trellis/tasks/archive/2026-09/09-04-dashboard-usage-periods/design.md 和 .trellis/spec/macos/data-persistence.md:53-61 明确 cache-first、多范围保留、仅缺失才请求、提交仅刷新当前范围。此次新需求需要替换后两项契约。
原始菜单栏任务明确手动刷新要 submit 后 fetch，打开只读；默认保留该操作边界。
已执行 trellis mem search '缓存'；检索主要命中当前对话与不相关价格/Node 任务，没有获得额外相关决策。以仓库归档和源码为依据。

## 外部依据
- RFC 5861：https://www.rfc-editor.org/rfc/rfc5861.html 。stale-while-revalidate 提供先返回旧响应、后台校验的思路；stale-if-error 讨论失败时继续使用旧响应。这里借鉴交互模式，自行维护展示快照，并非声称 Tokscale 已发送相应 Cache-Control。
- Apple Using the file system effectively：https://developer.apple.com/documentation/foundation/using-the-file-system-effectively 。Caches 用于可丢弃、改善性能的数据，Application Support 用于应用支持文件。推论：若离线打开可读是产品承诺，最后成功快照适合作为应用支持文件保留，而非仅作为可清理优化。首次安装/手动删除/损坏仍不能保证有真实数据。

## 方案比较
| 方案 | 优点 | 代价 | 建议 |
| --- | --- | --- | --- |
| 每范围按需刷新 | 请求少 | 范围混用不同批次，首次切换等待 | 不符合主要需求 |
| 全范围同时请求、各自发布 | 某范围失败不拖累其他范围 | 仍可能出现新旧混合 | 若用户重视局部新鲜度可选 |
| 全范围请求、一次发布完整统计快照 | 切换一致、更新安静、实现可控 | 任一统计失败整组保持旧版 | 推荐 |
| 本地直接解析原始用量 | 可绕过未上传延迟 | 重做聚合、价格和排名语义 | 本轮不建议 |

## 推荐技术轮廓（非已批准设计）
- Snapshot 包含 schemaVersion、username、generation、fetchedAt、四范围映射；区分本地获取时间和服务端 updatedAt。
- 只有完整且账号匹配的批次成为新快照。旧格式允许临时展示已存在范围，后台补齐后升级；旧独立时间戳不能伪装完整新批次。
- 刷新协调器合并 open/visible timer/wake/manual completion 请求；同时一个统计批次；手动提交期间避免启动冗余读，提交后必须有新的读取批次，不复用提交前结果。
- 切换账号立即隔离旧缓存与未完成任务；CLI 路径/版本切换也要防止旧状态响应回写。
- 候选 TTL 为 5 分钟，这是产品起点而非测得最佳值；失败退避可 30 秒→1 分钟→5 分钟，只在可见时重试，主动操作绕过自动退避。
- 全组请求需有超时，避免一个慢请求长期阻塞发布。关闭面板可允许已开始的短批次完成，停止定时触发；具体生命周期用测试验证。
- autosubmit 状态单独 fetchedAt、单独错误，不应因本机 npx 不存在冻结线上统计。是否也要求状态原子发布待用户确认。
- 统计全组一次发布仅保证客户端不展示半批数据。all/week/month 是多个 HTTP 请求，仓库已用接口没有共同快照版本契约；不能承诺服务端严格同一时刻。提交后的上游可见延迟亦未实测，不能承诺读取成功就一定包含刚提交用量。
- 检查 URLSession HTTP 缓存与服务器头部后确定重验证策略，不能仅凭 HTTP 200 或本地 fetchedAt 宣称源数据更新。
- 保留内容和选择、尽量保持滚动位置；无数据变动不做计数/布局动画。自动失败记录到轻量诊断，主动失败明确反馈。

## 验证重点
注入时钟及可控异步 API：过期/未过期、请求合并、全组部分失败、超时、切换账号/范围、提交与后台交错、关闭重开、睡眠唤醒、日期跨界。持久化验证旧格式迁移、损坏文件、写入失败、重启四范围恢复。UI 验证静默过程中内容/选择/布局稳定。实施前加载 macos/index.md、data-persistence.md、tokscale-integration.md、swiftui-guidelines.md。

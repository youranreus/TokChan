# 实施与验证清单

状态：待最终方案批准，不执行 task.py start。

1. 最终审阅后再进入实施；加载 trellis-before-dev 以及 macOS 状态、网络、持久化、SwiftUI、Tokscale 集成和测试规范。记录本任务明确取代的旧契约。
2. 增加全组 API 读取及测试：all/week/month 三次请求、共享 week 派生 day、范围/账号校验、一个失败整组失败、有限超时与 HTTP 缓存重验证行为。
3. 定义完整统计快照与状态独立时间；实现新路径、schemaVersion、旧多范围/单范围迁移和原子保存。验证损坏、账号不匹配、选择/状态保存不刷新统计时间、写失败不丢原文件。
4. 重构 DashboardViewModel 读取为统一批次：单任务合并、账号/generation 隔离、单次发布、失败保留旧数据、状态独立完成；注入时钟。更新所有 fake/preview API 实现。
5. 接入显示/隐藏与定时触发，确认 macOS 13 MenuBarExtra 生命周期。关闭后不发新请求，允许正在执行的短批次完成；唤醒无补跑风暴。
6. 将 refresh/run-now/saveSettings 的相关读取接入整组入口，确保提交前请求不能覆盖提交后结果；不增加任何静默 submit/run 操作。
7. 调整 UI：安静的更新时间、跨日实际日期、可访问错误详情；后台不占用按钮进度，保持用户当前选择和同范围滚动/展开状态，手动操作仍反馈结果。
8. 运行针对行为的确定性测试：TTL 边界、重复打开/关闭、并发合并、部分失败、超时、账号/范围切换、手动与后台交错、状态独立失败、首次无数据、跨日与睡眠。替换旧“有缓存始终零请求”“提交只有当前范围一次 fetch”断言，保留身份隔离与范围正确性覆盖。
9. 运行下列全量测试与 Release 构建；固定 fixture 检查明暗外观、长错误、跨日/离线及 380×680 布局，无真实上传。
10. trellis-check 验证整个变更范围；trellis-update-spec 同步 data-persistence.md、swiftui-guidelines.md、tokscale-integration.md 及必要状态/测试契约。记录验证结果后按项目流程收尾。

## 验证命令
```sh
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-cache-refresh-test
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -destination 'platform=macOS' -derivedDataPath /private/tmp/TokChan-cache-refresh-release build
```
Swift 编译检查由 Xcode 构建覆盖；如仓库存在实际 lint 配置再运行，不假定安装第三方 lint 工具。

## 高风险文件与验证对应
- TokChan/Features/Dashboard/DashboardViewModel.swift：AC2–AC6，请求竞态、统一发布、触发去重。
- TokChan/Shared/Services/TokscaleAPIClient.swift：AC2/AC4，批次读取、日期派生、HTTP 行为。
- TokChan/Shared/Services/DashboardCacheStore.swift：AC1/AC8，格式和路径迁移、失败回退。
- TokChan/TokChanApp.swift 与 DashboardView.swift：AC3/AC7，真实面板生命周期和静默交互。
- TokChanTests/DashboardViewModelTests.swift、DashboardCacheStoreTests.swift、PeriodAPITests.swift、DashboardLayoutTests.swift、DiscoveryRaceTests.swift：新旧行为覆盖与回归。

## 退回点
先稳定服务与模型测试，再接入调度和 UI；生命周期不可靠时先解决面板可见性，不以应用整体活跃状态代替。产品行为若需改变，回到最终方案审阅。数据层仅触及展示快照，可回滚代码，不删除旧缓存或修改远端数据。

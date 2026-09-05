# 执行计划

首版编辑范围已确认，PRD 已收敛。当前等待 Trellis 最终规划评审；得到后续明确批准后才运行 task.py start。

1. 重新检查工作树与最新设置页，读取 macOS specs、任务研究及状态管理合同。保护本轮开始前已有的 README、工程文件、发布脚本等其他任务改动。
2. 固定已支持的 Tokscale 输出 fixture，核实 v4.15.0 与计划支持的较新版本；确定 provider/model 拆分和每 Token 别名优先级。对未知格式采用明确的不可判断状态。
3. 实现价格文档和文件服务。覆盖缺失文件、有效文件、损坏 JSON、外部变化、未知字段、阶梯价格和原子写入失败。真实用户文件仅在手动验收时按授权编辑；自动测试用临时目录。
4. 扩展 CLI 命令及服务，添加覆盖列表读取、dry-run 和诊断解析。保留完整 stdout/stderr 给解析器，同时约束 UI 展示长度。用 fake runner 验证参数确实包含 --dry-run。
5. 实现局部 ViewModel 与表单状态，文件操作和检测的过期保护；接入原生自定义价格 Tab，避免调用原有 saveSettings。
6. 验证添加/编辑/删除/重新检查全流程，包括编辑预填与取消、已有条目补齐缓存价、每 Token 别名更新与清空、不生成重复条目、未知字段和阶梯字段保留。用 fixture 驱动 UI，覆盖长模型、14+ 条记录、零价、空值、无数据、失败和明暗模式。
7. 按 Trellis check 做增量检查及回归验证，更新 Tokscale integration spec 中 custom-pricing 专属文件操作边界；最终报告变更与验收结果。提交/归档按届时工作流程执行，不包含其他任务改动。

## 验证命令

- `xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'`，实现阶段根据新增用例选择针对性测试，最终运行必要回归。
- macOS 13 deployment target 下编译，不使用更高系统独占控件。
- 测试不得实际运行真实 submit、修改真实 autosubmit 或读取 token；CLI 集成测试使用 fixtures/fake runner。
- 手动验收：已定价、存在缺价、全部缺价、格式未知、外部修改、写入失败；检查键盘、表格滚动及系统明暗外观。

## 风险文件与回退

SettingsView 共享 footer、CLIService 协议及测试 fake、应用依赖注入是回归重点。保持价格页局部边界以便移除；回退代码不自动删除用户价格文件。工程文件如需调整，先对照其他任务未提交改动，避免整体覆盖。

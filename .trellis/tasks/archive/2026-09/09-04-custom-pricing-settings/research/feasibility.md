# 可行性调研

调研日期：2026-09-04。结论：可实现，原生 UI 与现有执行器可复用；主要复杂度在无损文件修改和文本诊断兼容。

## 本地验证

- 安装包 tokscale/package.json：版本 4.15.0。
- `tokscale submit --help`：支持 dry-run、客户端和日期过滤，没有 submit 专用 JSON 选项。
- `tokscale pricing --help`：支持单模型查询、list-overrides、JSON 输出，没有增删写操作。
- `tokscale pricing list-overrides --json`：返回 path/count/models；本机路径为 ~/.config/tokscale/custom-pricing.json，共 14 个有效条目。输出是解释后的价格投影，并不包含原文件的全部字段。
- 只读检查真实文件结构：根节点为 $schema/models，现有模型条目包含四类基础价格、source、notes。未修改真实价格文件。
- 实际执行默认 `tokscale submit --dry-run`，沙盒首次运行遇到 models.dev 网络及 source-message-cache 写权限警告；按权限流程在正常环境重试后退出码为 0，无缺价警告，扫描日期 2026-07-08 至 2026-09-04，三个客户端、八个模型，终端确认没有提交。检测结果受扫描范围和当时文件内容限制，不能等同于模型永久有价。
- dry-run 确实尝试同步 Cursor 数据，因此它是“不提交用量”的预检，不是零网络、零缓存写入操作。未调用真实 submit、未读取或输出凭据内容。

## 上游合同与来源

[官方 README 的价格覆盖说明](https://github.com/junhoyeo/tokscale#custom-pricing-overrides)明确了美元／百万 Tokens、大小写不敏感的精确匹配、部分 synthetic 模型路径归一化、零值与缺失值的区别。覆盖表以模型 ID 为键，不能将诊断中的 provider/model 整串原样当作键。

[4.15.0 CLI 源码](https://github.com/junhoyeo/tokscale/blob/v4.15.0/crates/tokscale-cli/src/main.rs)已下载到临时文件并核对真实行号：3823 的列表函数只投影四个基础单价；5750 的缺价报告逐项输出，没有条数上限；5849 的提交函数先检查登录，再扫描，6004 的 dry-run 分支在上传请求之前返回。无可提交 Tokens 分支更早返回，所以全部缺价时可能没有通常的 dry-run 结束句，解析必须先保留缺价信息。stdout 含主要诊断，stderr 可能包含数据源警告。

[当前 main 源码](https://raw.githubusercontent.com/junhoyeo/tokscale/main/crates/tokscale-cli/src/main.rs)在调研时已使用另一种缺价警告，描述以零成本保留用量并标记成本不完整；4.15.0 则描述排除缺价用量。README 与分支可能不同步，因此 UI 统一表达“缺失价格”，原文作为详情保留，不承诺所有版本都排除用量。main 是可变引用，实施时重新核对并固定 fixture。

[自定义价格解析器](https://raw.githubusercontent.com/junhoyeo/tokscale/main/crates/tokscale-core/src/pricing/custom.rs)支持基础价、阶梯价、每 Token 兼容字段，未知元数据不参与计算；错误条目可能被跳过。因此 CLI 列表不能当作原文件的无损表示，写入应操作原始 JSON 文档。

[配置目录解析](https://raw.githubusercontent.com/junhoyeo/tokscale/main/crates/tokscale-core/src/paths.rs)优先 TOKSCALE_CONFIG_DIR；macOS 默认 ~/.config/tokscale。环境变量可接受相对路径，不能擅自改用 macOS Application Support。建议以同一 CLI 上下文返回的 path 为准，确保文件服务与执行器环境、工作目录一致。

## 原生 UI 选择

[Apple 的 macOS SwiftUI 讲解](https://developer.apple.com/videos/play/wwdc2021/10289/)直接展示 Settings 场景中的 TabView，系统负责偏好设置工具栏外观。[SwiftUI Table 文档](https://developer.apple.com/documentation/SwiftUI/Table)提供列、选中和排序能力；[WWDC21](https://developer.apple.com/videos/play/wwdc2021/10018/)说明 macOS 原生多列表格的使用方式。所需基础控件均可在 macOS 13 方案中使用。

建议沿用 Settings/TabView，价格列表采用 Table，输入表单采用 Form/TextField，添加采用 sheet，删除采用系统 alert/confirmationDialog，进度采用 ProgressView。使用 SF Symbols、系统颜色和默认控件样式，不绘制标题栏、选中底板或自定义表格边框。为长模型 ID 和价格列适当增加设置窗口宽度；最终宽高通过真实 SwiftUI 预览/运行验证，不以手绘稿作为实现合同。

## 现有仓库接入点

- SettingsView.swift:53 新增 Tab；:83 的共享 footer 需允许价格页使用独立操作区。
- DashboardViewModel.swift:172 的 saveSettings 会配置自动提交，不能用于保存价格。
- TokscaleCLIClient.swift:133 已保留 stdout/stderr/exitCode，:241 是服务协议，:339 是运行边界。现有错误显示最多 4000 字符，完整诊断不能先经该截断再解析。
- 项目目标 macOS 13。Shared/Services 放文件服务与 CLI 适配，Features/Settings 放页面及局部 ObservableObject。无需引入数据库、WebView、npm UI 库或新的定时器。
- .trellis/spec/macos/tokscale-integration.md 的旧规则笼统禁止直接编辑配置文件。本次用户明确要求管理 custom-pricing.json，授权范围覆盖该文件；实施时将 spec 收敛为仅允许自定义价格文件，继续保留凭据、settings.json 和调度器边界。该历史规则不需要额外向用户申请任务许可。

## 剩余工程风险

- latest 指向变化：按运行版本/已识别格式判断，未知内容不能报告零缺价。
- 提供方与模型由斜杠连接，而模型自身也可能含斜杠；保留原串，按已验证的 provider 结构拆分，无法确定时允许手动核对，不将整串悄悄写入模型键。
- 上游会重载每个新进程的覆盖文件；保存完成后启动新 dry-run 即可验证。价格修改必须使旧报告过期。
- 外部编辑器可能同时写文件；采取写前比较原始内容及原子替换，遇到冲突要求重新载入。原子替换避免半文件，但不能声称与不合作的外部写入者完全无竞态。
- 现有阶梯价和未知字段保留；本次表单只编辑基础字段。需要明确每 Token/每百万别名优先级，避免编辑后旧字段覆盖新值。

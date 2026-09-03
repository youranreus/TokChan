# 构建 Tokscale macOS 状态栏查看应用

## Goal

构建一个最低支持 macOS 13 的原生 SwiftUI 状态栏应用，让用户无需打开终端即可在紧凑的竖长面板中查看 Tokscale 在线统计，并通过 GUI 读取和管理 Tokscale 自带的 autosubmit。手动刷新必须先提交本地用量，成功后再读取线上最新资料。

## Background

仓库目前只有 Trellis 配置，没有 SwiftUI 工程或应用源码。Tokscale 已提供公开资料 API、`submit` 命令和基于 macOS `launchd` 的 autosubmit，因此本应用只负责原生展示与 CLI 编排，不实现 Tokscale 服务端，也不维护第二套提交调度器。

已核实的集成事实：

- 当前开发机安装了 `tokscale 4.15.0`，`tokscale whoami` 显示已登录用户 `youranreus`。
- Tokscale 公开资料接口为 `GET https://tokscale.ai/api/users/<username>`；MVP 使用 lifetime 数据，响应包含汇总指标、排名、更新时间，以及带客户端和模型明细的每日贡献记录。
- `tokscale autosubmit status --json` 返回启用状态、分钟间隔、调度器、客户端/日期筛选、托管可执行文件及版本、最近运行时间和最近错误。
- `autosubmit enable`、`disable` 和 `run --force` 是受支持的配置与执行入口；macOS 调度由 Tokscale 管理的 `launchd` 完成。
- 当前开发机的 autosubmit 已启用，间隔为 120 分钟，调度器为 `launchd`，托管版本为 `4.15.0`，没有客户端或日期筛选，也没有最近错误。

## Requirements

- 提供常驻 macOS 状态栏入口，不依赖主窗口保持打开；应用不显示 Dock 图标。
- 点击状态栏图标后显示竖长型、紧凑的自定义面板，而不是传统菜单列表。
- 首屏顶部展示用户身份、总 Token、总成本、排名、活跃天数和线上更新时间。
- 首屏下方展示客户端与模型分组列表。每个客户端展示 Token、成本和占总量比例，组内列出其模型；客户端及组内模型默认按 Token 降序排列。
- 打开面板时读取线上资料和 autosubmit 状态，但不自动执行提交。
- 手动刷新时先通过配置版本的 Tokscale CLI 提交本地用量；提交成功后再请求线上资料，提交失败时不显示刷新成功。
- 通过 `autosubmit status --json` 读取并展示当前 autosubmit 的启用状态、间隔、调度器、筛选条件、托管版本、最近运行时间和最近错误。
- 通过 GUI 调用 `autosubmit enable` / `disable` 管理启停、间隔、客户端筛选和日期范围筛选；不直接编辑 Tokscale 的 `settings.json` 或 LaunchAgent。
- 提供立即运行 autosubmit 的操作，通过 `autosubmit run --force` 执行，并在完成后重读状态和线上资料。
- 版本设置实际控制 npm 包版本，命令采用等价于 `npx --yes tokscale@<version> ...` 的参数化执行方式；不得使用 shell 字符串拼接。
- 自动定位 `npx`，并允许用户在定位失败时指定绝对路径。Finder 启动环境不得依赖交互式 shell 的 `PATH`。
- 通过 `tokscale whoami` 尝试发现用户名，并允许用户在设置中覆盖；只持久化用户名、Tokscale 版本和 `npx` 路径等小型偏好。
- 不读取、展示或另行持久化 Tokscale API token；沿用 Tokscale 自己的登录与凭据机制。
- 网络、CLI 和持久化操作位于可替换的服务边界，异步执行且不阻塞 UI。
- 提供清晰的加载、空数据、CLI 缺失、登录缺失、提交失败、API 失败和 autosubmit 配置失败反馈。
- 将最近一次成功的资料汇总与 autosubmit 状态缓存到本地；再次打开面板时立即展示缓存并在后台更新，不以全屏 loading 覆盖已有内容。
- 设置使用独立的 macOS Settings 窗口，不能以内嵌 sheet 覆盖状态栏浮窗。
- 所有用户可见的界面文字和错误提示使用中文。
- 状态栏面板及设置窗口不使用分割线，以留白、卡片背景和分组间距组织层级。

## Acceptance Criteria

- [x] 应用在 macOS 13 或更高版本构建并运行，启动后仅出现在状态栏。
- [x] 点击状态栏图标后出现竖长紧凑面板；顶部总览和客户端/模型分组列表均在同一可滚动首屏中。
- [x] lifetime 在线数据成功时展示总 Token、总成本、排名、活跃天数、更新时间及完整的客户端到模型归属；列表默认按 Token 降序。
- [x] 请求中、无提交记录、用户名无效、网络失败和解码失败都有明确状态，不会崩溃或保留误导性的成功提示。
- [x] 打开面板只读取远端资料和 autosubmit 状态，不会触发 `submit`。
- [x] 手动刷新可验证为先执行提交、成功后再请求远端资料；提交失败时停止后续在线读取并显示可理解错误。
- [x] GUI 准确显示 `autosubmit status --json` 返回的启用状态、间隔、调度器、筛选、托管版本、最近运行时间和最近错误。
- [x] 修改 autosubmit 后通过 Tokscale CLI 生效；启用、禁用、间隔、客户端筛选和日期范围筛选均可用假 CLI 验证命令参数。
- [x] “立即运行”调用 `autosubmit run --force`，完成后重读 autosubmit 状态和在线资料，任务期间界面保持响应。
- [x] 设置的 Tokscale 版本参与后续 `npx --yes tokscale@<version>` 命令；重启应用后用户名、版本和 `npx` 路径仍保留。
- [x] 所有外部命令均使用可执行文件与参数数组执行；版本值和路径经过校验，不形成 shell 注入入口。
- [x] 单元测试覆盖资料 JSON 解码与聚合排序、autosubmit JSON 解码、偏好持久化、命令构造、刷新顺序以及主要成功/空数据/失败状态，且不访问真实网络或真实 `launchd`。
- [x] `xcodebuild build` 和 `xcodebuild test` 针对 TokChan scheme 通过。
- [x] 已有缓存时，打开状态栏面板立即展示上次成功数据，同时后台更新；首次无缓存时才展示加载占位。
- [x] 资料或 autosubmit 任一成功更新后写回紧凑 JSON 缓存；缓存损坏时安全忽略且不影响在线加载。
- [x] “设置”打开独立窗口，关闭设置不会关闭状态栏应用，浮窗中不再呈现设置 sheet。
- [x] 主面板、设置窗口和用户可见错误提示均为中文。
- [x] `TokChan` 源码中不再存在 `Divider()`，界面依靠间距与背景层级组织。

## Out of Scope

- 不实现 Tokscale 服务端、远端 API 或自己的定时提交调度器。
- 不直接编辑 `~/.config/tokscale/settings.json`、autosubmit 日志、LaunchAgent 或任何 token 文件。
- 不实现 Tokscale 登录、API token 管理、多账户切换或账户删除。
- 不实现贡献日历、历史趋势图、数据导出、通知中心提醒或完整 Tokscale TUI 功能复刻。
- MVP 不提供 lifetime / 30 天 / 7 天切换，固定展示 lifetime 在线数据。
- 不以 Mac App Store 沙盒分发为目标；执行本地 CLI、读取其状态并管理 `launchd` 需要非沙盒应用能力。

## Deferred Items and Risks

- Tokscale 公开 API 没有独立的聚合客户端列表；应用需要从 `contributions[].clients` 汇总客户端和模型数据，并对缺失/新增字段做兼容解码。
- Finder 启动的环境可能找不到 NVM 中的 `npx`；实现需覆盖常见安装位置并提供手动路径设置与诊断。
- `npx` 首次解析指定版本时可能联网下载，耗时明显；界面需显示进行中状态并保留标准错误输出。
- Tokscale API 和 CLI JSON 属于外部契约，未来可能变化；模型字段采用容错解码，CLI 非零退出与 JSON 解码错误应明确区分。

# 改进新手引导与 Agent 登录

## Goal

减少首次启动时的隐式行为，让用户明确决定何时读取本机 Tokscale 身份，并为 Cursor 用户提供无需先打开终端的自动登录入口。

## Background

- 当前用户名为空时，应用启动会自动执行 Tokscale `whoami`，引导页只显示不可操作的识别进度。
- 当前引导页支持手工填写用户名、验证公开统计和首次提交，但没有客户端专项登录入口。
- 当前设置页已有 Tokscale 版本和 npx 路径配置，也有统一的 CLI 操作反馈。
- Tokscale 的 Cursor 登录优先读取已登录的 Cursor 桌面会话；无法自动发现时可能要求交互粘贴 token。
- Cursor 登录本身不需要在本功能中继续执行显式同步。后续 Tokscale submit 会按上游规则包含 Cursor 的 best-effort 同步。

## Requirements

### R1 手动身份识别

- 初始未配置且用户名为空时，引导页进入可操作的账号连接状态，不自动执行 `whoami`。
- 引导页保留手工输入 Tokscale 用户名的能力，并增加“识别本机登录”按钮。
- 只有用户点击该按钮后才执行一次身份识别。
- 识别成功后保存规范化用户名，并沿用现有流程验证完整统计。
- 识别失败后保留手工输入能力，并显示可恢复的失败信息。

### R2 Cursor 自动登录

- 首期特殊 Agent 仅支持 Cursor。
- 引导页账号连接区域展示不阻塞主流程的可选 Cursor 登录模块。
- 设置页也提供同一 Cursor 自动登录能力。
- 用户点击后，使用当前有效 npx 路径和 Tokscale 版本执行 `cursor login`。
- 登录成功后显示成功反馈，不额外执行 `cursor sync`、提交或统计刷新。
- 登录失败或 CLI 无法在应用内完成交互式 token 输入时，显示失败原因以及可复制的终端命令，供用户在终端继续。

### R3 操作与安全

- 身份识别和 Cursor 登录都必须有明确的进行中、成功或失败状态，并拒绝重复点击。
- TokChan 不读取、采集、保存或转发 Cursor Cookie/token，凭据仍由 Tokscale 管理。
- Tokscale 命令使用离散参数执行，不通过 shell 拼接。
- 登录流程兼容当前的 Tokscale 版本校验、npx 定位、子进程 PATH、超时和错误截断约定。
- 自动后台路径不得触发 Cursor 登录。

## Acceptance Criteria

- [x] AC1：用户名为空的首次启动记录零次 `whoami`，引导页可立即手工输入用户名。
- [x] AC2：点击“识别本机登录”恰好执行一次 `whoami`；成功时保存用户名并执行一次完整统计验证。
- [x] AC3：手动识别失败时仍停留在可编辑账号连接状态，显示错误且可以再次尝试。
- [x] AC4：引导页中的 Cursor 模块为可选项，不阻塞手工填写用户名或继续引导。
- [x] AC5：引导页和设置页的 Cursor 登录按钮都执行准确的 `npx --yes tokscale@<version> cursor login` 参数序列。
- [x] AC6：Cursor 登录成功后不执行 `cursor sync`、`submit`、统计拉取或 autosubmit 状态读取，并显示成功反馈。
- [x] AC7：Cursor 登录失败时显示可恢复错误和可复制的 `npx tokscale@<version> cursor login` 终端命令；TokChan 不提供 token 输入框。
- [x] AC8：身份识别或登录运行期间按钮禁用，重复操作不会启动第二个进程。
- [x] AC9：无效版本、缺失 npx、非零退出和超时沿用现有可读错误处理，且不启动 shell。
- [x] AC10：相关 ViewModel、命令构造、服务和固定尺寸 SwiftUI 布局测试通过，UI 测试不访问真实网络或 npx。

## Constraints

- 继续使用现有 380×680 Dashboard 根视图、原生 SwiftUI 控件和局部卡片背景。
- 设置窗口继续由现有 SwiftUI `Settings` scene 与原生 TabView 管理。
- 不新增 onboarding-complete 持久化标记。
- 使用用户当前保存的 Tokscale 版本；终端回退文案按该版本生成。

## Out of Scope

- Trae、Warp 或其他客户端专项登录。
- 在 TokChan 内进行交互式 Cookie/token 输入。
- Cursor 多账号标签、状态、切换、登出或缓存清理。
- 登录后显式执行 `cursor sync`。
- 改变 Tokscale submit 自身的 Cursor 同步行为。

## Open Questions

无阻塞问题。

# Tokscale 客户端登录调研

## Sources

- Tokscale upstream repository: `https://github.com/junhoyeo/tokscale`，调研时读取默认分支最新源码。
- `README.zh-cn.md` 的 Cursor、Trae、Warp 命令章节。
- `crates/tokscale-cli/src/main.rs` 中的 `CursorSubcommand`、`TraeSubcommand`、`WarpSubcommand` 与 Cursor 自动同步逻辑。

## Findings

- Cursor 登录命令为 `tokscale cursor login [--name <label>]`。
- Cursor 登录会优先从已登录的 Cursor 桌面端读取会话；无法自动发现时，CLI 回退为交互式粘贴浏览器 token。
- Cursor 登录本身只保存认证。Tokscale 的本地报告/提交路径在 Cursor 已登录、缓存需要刷新且客户端过滤包含 Cursor 时，会执行 best-effort 自动同步；显式 `cursor sync` 可绕过缓存新鲜度门槛。
- Trae 也有独立 `login`/`sync`，可自动发现或交互粘贴 JWT；Warp 登录需要 bearer token 或 cookie。它们不属于本任务首期范围。

## Product Decisions

- 首期仅支持 Cursor。
- TokChan 只尝试 Cursor 桌面会话自动登录，不在应用内接收 Cookie/token。
- 自动登录失败时展示失败信息和可复制的终端命令，由用户在终端完成交互式回退。
- 登录成功后不额外执行 `cursor sync --json`，后续 Tokscale submit 路径负责按上游策略同步。

# 重写开源仓库 README

## Goal

把根目录 README 改成面向普通使用者与潜在贡献者的中文项目首页。读者打开仓库后，应能快速看懂 TokChan 是什么、它与 Tokscale 怎样配合、目前能做什么、怎样安装，以及遇到 macOS 安全提示或 Cursor 数据缺失时该怎样处理。

## Background

- TokChan 是原生 macOS 状态栏应用，最低支持 macOS 13，当前项目版本为 0.2.1。
- TokChan 从 `https://tokscale.ai/api/users` 读取公开资料，并通过 `npx --yes tokscale@<版本>` 调用 Tokscale 官方 CLI。Tokscale 负责扫描本地客户端数据、登录、提交、自动提交与价格配置，TokChan 提供图形界面和状态栏入口。
- TokChan 不保存 Tokscale 凭据。应用本地只保存用户名、Tokscale 版本、可选的 `npx` 路径、界面偏好和统计快照。
- 当前 Release 使用 ad-hoc 签名，未使用 Developer ID 签名，也未经过 Apple 公证。首次启动可能被 Gatekeeper 拦截。
- Cursor 数据由 Tokscale 经 Cursor API 同步到 `~/.config/tokscale/cursor-cache/usage*.csv`。Tokscale 不读取 `~/.cursor` 中的本地会话，因此未完成 Cursor 登录与同步时，统计里不会出现 Cursor 数据。
- 仓库目前没有可直接用于 README 的产品截图，需要用应用自带的 UI 测试预览数据生成一张主面板截图，并明确这是演示数据。
- 仓库根目录目前没有项目许可证文件，因此 README 不声明 TokChan 使用某种开源许可证，也不添加许可证徽章。

## Requirements

- 全文使用中文，保留命令、路径、产品名和必要的代码字段原样。
- 页面顺序为 Logo、名称与一句话介绍、少量徽章、主界面截图、功能简介、TokChan 与 Tokscale 的关系、功能详细说明、安装与使用、常见问题、开发构建、致谢。
- Logo 使用仓库现有的 `BrandAssets/Sources/TokChan_transparent.png`。
- 徽章只展示可以从仓库直接核验的信息，例如当前 Release、macOS 13+ 和 Swift 5，不展示不存在的许可证或未经验证的下载量。
- 新增一张适合 GitHub README 展示的主面板截图，使用预览数据，避免暴露真实用户名、头像或用量。
- 功能列表覆盖四个统计范围、总 Tokens 与成本、排名和活跃天数、五类 Token 构成、客户端与模型明细、状态栏摘要、提交与刷新、右键推送和拉取、本地缓存、登录时启动、自动提交管理、自定义价格、`npx` 自动探测与手动覆盖。
- 清楚说明 TokChan 依赖 Tokscale，但不属于 Tokscale 官方项目。Tokscale 仍是数据采集、提交、账号状态与自动提交的事实来源。
- 安装说明优先面向 Release 用户，给出下载 DMG、拖入 Applications、首次打开和 Node.js/`npx` 前置条件。源码构建说明保留为次要内容。
- FAQ 至少回答首次启动为何需要在系统设置中手动允许、为何默认没有 Cursor 数据、为何菜单栏有图标而程序坞没有、刷新按钮会做什么、为什么需要 Node.js 与 `npx`、数据与凭据存在哪里、自定义价格怎样生效。
- 安全说明准确保留当前 ad-hoc 签名和未公证事实，不把现有构建包装成适合无提示公开分发的正式签名版本。
- 致谢 Tokscale 与其作者 Junho Yeo，说明客户端图标来源及随附的 Tokscale MIT 许可证，并保留 TokChan 作者季悠然的链接。
- 链接尽量使用稳定入口，包括 Tokscale 官网、Tokscale GitHub、TokChan Releases 和作者主页。

## Acceptance Criteria

- [x] README 从开头到致谢均为中文，命令和专有名词除外。
- [x] 首屏能看到 Logo、TokChan 标题、可核验徽章、简短介绍与主界面截图。
- [x] README 明确区分 TokChan 图形界面和 Tokscale 上游能力，不暗示 TokChan 自己解析所有客户端数据，也不暗示官方隶属关系。
- [x] README 的功能清单与当前 Swift 源码和测试一致。
- [x] FAQ 给出可执行的 macOS Gatekeeper 处理步骤和 Cursor 登录、同步命令。
- [x] 新截图只含预览数据，路径在仓库内有效，Markdown 可在 GitHub 正常显示。
- [x] README 不声明仓库中不存在的许可证、签名、公证或平台支持。
- [x] `human-writing` 检查脚本通过，Markdown 链接与本地图片路径经过检查。
- [x] Git diff 仅包含 README、README 使用的截图资源和本 Trellis 任务记录。

## Out of Scope

- 不修改 TokChan 功能、界面文案、版本号、构建或 Release 工作流。
- 不新增项目许可证，不替仓库所有者选择许可证。
- 不申请 Developer ID、不做 Apple 公证，也不发布新的 Release。
- 不翻译代码、测试、Release 脚本或 Trellis 规范。

## Technical Notes

- 这是轻量文档任务，只需要 `prd.md`，不创建 `design.md` 或 `implement.md`。
- README 事实以当前源码、项目配置、Release 工作流和 Tokscale 上游 README 为准。
- 截图可通过 `--ui-testing` 预览环境生成，主面板预览数据定义在 `TokChan/Features/Dashboard/DashboardView+Preview.swift`。

# 兼容常见 Node 版本管理器探测

## Goal

让从 Finder/LaunchServices 启动的 TokChan 能在没有交互式 shell `PATH` 的情况下，自动找到常见 Node 版本管理器所安装的可执行 `npx`，减少手动路径配置。

## Background

- 当前定位器仅检查用户覆盖、继承 `PATH`、Homebrew/系统固定路径及默认 `~/.nvm/versions/node/*/bin/npx`。
- 本机使用 fnm，实际稳定安装路径为 `~/.local/share/fnm/node-versions/v24.14.1/installation/bin/npx`；shell 中的 `~/.local/state/fnm_multishells/*/bin` 是临时路径，Finder 启动时不可用。
- 调研确认其他常见管理器也依赖 shell 初始化、shim 或自定义根目录，不能通过启动登录 shell安全地恢复环境。
- 详细路径、来源和风险见 `research/node-manager-paths.md`。

## Requirements

- R1：保留现有优先级前段：有效用户覆盖 → 继承 `PATH` → Homebrew/系统固定路径。
- R2：增加 fnm、Volta、asdf、mise、nodenv、n 和 nvm 的稳定默认目录与绝对环境变量根目录探测。
- R3：优先采用无需 shell 初始化即可执行、能够表达用户默认选择的稳定候选；无法安全解析默认选择时，回退到严格语义版本排序后的最新稳定安装。
- R4：不执行登录 shell、profile、版本管理器命令或可能触发安装/联网的通用 shim；Volta 官方稳定 shim 可作为例外候选。
- R5：环境变量根目录只接受绝对路径；配置或别名文本只接受受限的精确版本，拒绝路径穿越、shell 语法和含糊版本表达式。
- R6：候选构建必须有限、确定、去重，并继续要求最终目标存在、不是目录且可执行。
- R7：继续在启动 `npx` 时将其所在目录置于子进程 `PATH` 前端，使 `#!/usr/bin/env node` 能解析同目录的 Node。
- R8：保持现有设置页状态、手动覆盖语义和偏好存储格式兼容。

## Acceptance Criteria

- [x] Finder 类精简环境下，本机默认 fnm 安装可自动解析到 `aliases/default/bin/npx`，无别名时回退到最新稳定安装。
- [x] Volta、asdf、mise、nodenv、n、nvm 的约定默认根目录均有成功探测测试。
- [x] 支持各管理器继承到进程中的绝对根目录覆盖，并忽略相对或恶意根目录值。
- [x] 默认/全局版本选择、严格语义版本回退、跨管理器确定性优先级均有测试。
- [x] fnm multishell、asdf/mise/nodenv 通用 shim、n 下载缓存不会被扫描或执行。
- [x] 无候选、断裂别名、目录伪装、不可执行文件和畸形版本目录均安全回退或返回缺失。
- [x] 现有 npx 设置、Tokscale 命令及完整 Xcode 测试继续通过。

## Out of Scope

- 自动安装 Node.js、npm 或版本管理器。
- 执行或解析用户 shell profile。
- 完整复刻各管理器的项目级版本解析、范围/LTS 解析或自动切换语义。
- 扫描任意自定义路径；仅 shell profile 中可见的非默认根目录继续使用手动覆盖恢复。
- Windows/Linux 路径兼容。

## Key Decisions

- 本次兼容范围覆盖 fnm、Volta、asdf、mise、nodenv、n、nvm 七类常见管理器。
- 文件系统直接探测优先于执行管理器或通用 shim；Volta 的原生稳定 shim 是唯一例外。
- 多个管理器同时安装时采用代码中固定且有测试的顺序；继承 `PATH` 或用户覆盖始终可表达用户明确选择。

# 调研构建与发布流程

## Goal

调研并实现仓库的构建、版本与发布机制，形成一套可落地、低维护成本的自助发布方案，使维护者可以在本地完成构建与版本递增，并通过 Git Tag 触发 GitHub Actions 自动构建和发布 GitHub Release。

## Background and Confirmed Facts

- TokChan 是原生 SwiftUI macOS 菜单栏应用，使用单一 `TokChan.xcodeproj` 和共享 `TokChan` scheme；ArchiveAction 使用 Release。
- 当前公开构建入口只有 README 中的 `xcodebuild ... build`，仓库没有统一构建、打包、版本递增脚本或 `.github/` workflow。
- 当前直接产物为 universal `TokChan.app`；仓库尚未定义 ZIP、DMG、PKG、checksum 或 Release 命名规范。
- 用户版本的权威来源为 app target Debug/Release 两处 `MARKETING_VERSION = 0.1.0`，构建号为两处 `CURRENT_PROJECT_VERSION = 1`；About 页从生成的 Info.plist 读取用户版本。
- 当前无 Git Tag 历史及发布提交约定。
- 工程使用 Automatic signing，但没有提交 Team、Developer ID identity、entitlements、导出或公证配置；App Sandbox 和 Hardened Runtime 均关闭。README 说明 Sandbox 因 Tokscale 本地访问与 LaunchAgent 能力而刻意关闭。
- 完整仓库证据见 `research/repository-current-state.md`；目标方案与官方资料见 `research/recommended-release-design.md`。

## Requirements

- 基于仓库现状识别应用类型、构建入口、产物格式、版本号来源、签名配置及现有自动化。
- 实现统一的本地自助构建入口，避免维护者记忆多条底层命令。
- 实现本地版本管理流程，至少支持 patch 版本递增、更新权威版本号与构建号、提交与创建 Git Tag。
- 实现 GitHub Actions 发布流程，在符合约定的 Tag 推送后构建 universal ZIP、生成 SHA-256，并通过 draft Release 事务发布。
- 规定并落实版本与 `vX.Y.Z` Tag 一致性、最小 Actions 权限、同 Tag 并发控制、已发布资产不可覆盖，以及失败恢复规则。
- 首版以维护者个人使用为目标，采用明确标注的未签名/adhoc ZIP，不引入 Developer ID、公证凭据或 Hardened Runtime 改造；公开分发前必须另行完成签名与公证加固。
- 更新维护者文档，并用脚本检查、Xcode 测试、产物校验和 workflow 静态检查验证实现。

## Acceptance Criteria

- [x] 调研文档列出当前构建、版本和发布机制的仓库证据。
- [x] `scripts/build-release.sh` 按设计提供参数、测试、unsigned universal 构建、校验、ZIP/checksum 输出和失败清理行为。
- [x] `scripts/release.sh patch [--push]` 实现构建号与 patch 版本递增、验证、release commit、annotated Tag 和可选原子推送。
- [x] `.github/workflows/release.yml` 实现严格 Tag 校验、最小权限、固定 runner/Xcode、测试门禁及 draft-to-published Release 状态机。
- [x] README 说明本地操作、资产校验、GitHub 设置要求，以及个人使用的未签名/未公证限制。
- [x] 脚本静态检查、单元测试、Release 构建、bundle/架构/ZIP/checksum 校验和 workflow 检查通过。
- [x] `design.md` 与 `implement.md` 和最终实现保持一致。

## Out of Scope

- 不在未确认分发策略前申请或配置外部开发者证书、Apple 公证凭据。
- 首版不设计 DMG/PKG、应用内自动更新、Mac App Store 分发或多架构独立 Release 包。

## Distribution Decision

首版 GitHub Release 仅供维护者个人使用。允许发布未 Developer ID 签名、未 Apple 公证的 universal ZIP，但构建日志与 Release notes 必须显式提示 Gatekeeper 限制。面向普通公众分发、Developer ID、公证、DMG/PKG 和应用内更新留待后续独立任务。

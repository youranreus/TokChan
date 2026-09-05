# 构建 macOS DMG 发布产物

## Goal

将当前 Release 产物从直接解压 App 的 ZIP 安装方式，优化为符合 macOS 用户习惯的 DMG 安装镜像。用户打开镜像后可看到 `TokChan.app` 与 `Applications` 文件夹入口，并通过拖拽完成安装。

## Background

- 当前 `scripts/build-release.sh` 构建 arm64/x86_64 通用 App，执行完整 ad-hoc 签名与校验，然后输出 ZIP 和对应 SHA-256 文件。
- `.github/workflows/release.yml` 只接受并上传这两个精确资产，发布前会校验资产列表。
- 当前发布仍是个人使用流程：App 不是 Developer ID 签名，也未公证；本任务不得弱化现有 Gatekeeper 风险提示。
- `README.md` 明确将 DMG 排除在现有 ZIP 发布流程之外，因此实现时必须同步更新发布文档。

## Requirements

- Release 构建应生成可挂载的 macOS DMG。
- DMG 根目录应展示 `TokChan.app` 和指向 `/Applications` 的文件夹入口。
- 用户应能将 `TokChan.app` 拖到该入口完成安装。
- DMG 内的 App 必须保留现有 universal 架构、版本元数据和完整 ad-hoc 签名校验约束。
- 构建流程必须验证 DMG 可挂载、预期内容存在、Applications 入口指向正确位置，并对从镜像读取的 App 重新执行签名校验。
- GitHub Release 工作流及 README 必须与最终资产集合、校验方式和个人使用安全提示保持一致。
- 最终命名继续包含版本号与 `macos-universal` 标识。

## Acceptance Criteria

- [x] 执行 Release 构建后生成版本化 DMG，并生成可验证该 DMG 的 SHA-256 文件。
- [x] 挂载 DMG 后，根目录包含 `TokChan.app` 和指向 `/Applications` 的入口。
- [x] 双击 DMG 后呈现简洁原生的固定 Finder 图标布局：App 在左、Applications 在右，无品牌背景图或其他用户可见项目。
- [x] 用户可以通过拖拽 App 到 Applications 入口执行标准安装。
- [x] 镜像中的 App 同时包含 arm64 与 x86_64，版本/构建号正确，且通过现有严格 codesign 校验。
- [x] Tag 触发的 GitHub Actions 能校验并上传约定的精确 Release 资产，然后发布 Release。
- [x] README 准确说明本地构建、产物校验、DMG 安装步骤及未公证风险。
- [x] 自动化脚本测试覆盖新的产物命名、拒绝覆盖、失败清理和工作流资产约束。

## Out of Scope

- Developer ID Application 签名、Apple 公证与 stapling。
- Mac App Store / PKG 分发。
- 自动更新机制。
- 改变应用运行时功能。

## Key Decisions

- GitHub Release 仅发布版本化 DMG 与其 SHA-256 文件；DMG 替换现有 ZIP，不保留双格式资产。
- DMG 使用简洁原生样式：固定 Finder 窗口与图标位置，只展示 `TokChan.app` 和 Applications 入口，不增加品牌背景图。

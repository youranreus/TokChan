# 修复发布包 ad-hoc Bundle 签名

## Goal

让 TokChan 的维护者个人使用版 GitHub Release 产出完整、可由 `codesign` 验证的 ad-hoc 签名 App Bundle，使安装到 `/Applications` 的应用能够被 `SMAppService.mainApp` 识别，同时明确保留“未使用 Developer ID、未公证、可能触发 Gatekeeper”的分发定位。

## Background

- 已安装的 TokChan 0.1.7 位于 `/Applications/TokChan.app`，Bundle ID 与版本正确，但 `codesign --verify --deep --strict` 报告 `code object is not signed at all`，`spctl` 拒绝该应用。
- 当前可执行文件只有 linker-generated ad-hoc 元数据：`Identifier=TokChan`、`Info.plist=not bound`、`TeamIdentifier=not set`；这不是完整 Bundle 签名。
- `scripts/build-release.sh` 显式设置 `CODE_SIGNING_ALLOWED=NO`、`CODE_SIGNING_REQUIRED=NO` 和空签名身份，并将产物描述为 unsigned。
- `SMAppService.mainApp.status` 因无法识别此发布包而返回 `.notFound`；应用位于 `/Applications` 不是本次故障原因。
- 用户接受其他下载者需要手动处理 Gatekeeper，不要求本次加入付费 Apple Developer Program、Developer ID 或公证。

## Requirements

- 发布构建继续不依赖 Apple Developer 账号、Developer ID 证书或私密 CI 凭据。
- 在打包 ZIP 之前，对完整 `TokChan.app` Bundle 执行确定性的 ad-hoc 签名，而不是仅依赖 Mach-O linker signature。
- 签名后的 designated identifier 必须为 `com.youranreus.TokChan`，Info.plist 和资源必须包含在签名封装中。
- 构建脚本必须在发布前执行严格 Bundle 签名验证，并在无效签名、错误 identifier 或签名步骤失败时 fail closed，不发布 ZIP/校验和。
- ZIP 解压后的 App Bundle 必须再次通过签名验证，防止打包过程损坏签名。
- 保持 universal `arm64` + `x86_64`、版本、校验和、并发发布锁及不可覆盖行为不变。
- 更新 README、GitHub Release 警告、脚本输出和 macOS 发布规范，准确区分“完整 ad-hoc 签名”与“Developer ID 签名/Apple 公证”。
- 扩展发布脚本 fixture 测试，验证签名命令、失败关闭和压缩后复验；测试不得需要真实开发者证书。

## Acceptance Criteria

- [ ] `scripts/build-release.sh` 生成的原始 `TokChan.app` 通过 `codesign --verify --deep --strict --verbose=2`。
- [ ] `codesign -dv` 显示 Bundle identifier 为 `com.youranreus.TokChan`，且 Info.plist/资源由 Bundle 签名覆盖。
- [ ] 从最终 ZIP 解压出的 `TokChan.app` 仍通过严格 `codesign` 验证。
- [ ] 签名或复验失败时，脚本非零退出，且不留下最终命名的 ZIP 或 SHA-256 文件。
- [ ] 发布脚本测试覆盖成功、签名失败和压缩后验证失败场景。
- [ ] `bash -n`、项目版本测试、发布脚本测试、完整发布构建及现有 Xcode 测试通过。
- [ ] 用新产物替换 `/Applications/TokChan.app` 后，`SMAppService.mainApp` 不再因 Bundle 不可识别而固定返回 `.notFound`；实际注册仍由用户通过应用开关触发。
- [ ] 所有公开说明明确：ad-hoc 签名不提供开发者身份或公证，其他用户仍可能需要手动放行 Gatekeeper。

## Out of Scope

- 购买或配置 Apple Developer Program。
- Developer ID Application 签名、Hardened Runtime、公证或 Stapling。
- Mac App Store、DMG/PKG、自动更新或证书轮换。
- 自动修改用户 Gatekeeper 设置、清除 quarantine 或注册系统登录项。
- 在本任务中自动创建并发布新版本或 Git Tag。

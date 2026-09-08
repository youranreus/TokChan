# macOS 签名、公证与 GitHub 发布

正式发布使用 Developer ID Application 签名、Hardened Runtime、可信时间戳和 Apple 公证。App 与 DMG 都装订公证票据，最后生成 SHA-256 校验文件。签名、公证、打包或 Release 资产校验失败时，CI 不会发布 Release，也不会降级为 ad-hoc 签名；若 Release 发布后的 Pages 部署失败，已部署的旧 feed 保持不变，并进入仅恢复 feed 的重跑路径。

本流程适用于后续通过新工作流发布的版本。历史 Release 不会自动获得签名或公证，已发布的 Tag 和附件不应覆盖。

## 1. 创建并导出签名证书

1. 确认已开通 Apple Developer Program，并已接受账号内待处理的协议。
2. 在 Xcode 的 Settings → Accounts 添加 Apple 账号，选择对应 Team，进入 Manage Certificates，创建 **Developer ID Application** 证书。请勿选择 Apple Development、Apple Distribution 或 Developer ID Installer。创建 Developer ID 证书可能需要 Account Holder 操作。
3. 打开 macOS“钥匙串访问”，在“我的证书”中找到 `Developer ID Application: 姓名或组织 (TEAMID)`。展开后应能看到私钥。只有 `.cer` 文件不足以在 CI 签名。
4. 将证书连同私钥导出为 `.p12`，设置一个非空的导出密码。
5. 在终端将文件转为 Base64 并复制到剪贴板，替换下方示例路径。

```bash
base64 -i "$HOME/Downloads/DeveloperID.p12" | pbcopy
```

完整证书名称用于 `APPLE_SIGNING_IDENTITY`，括号内的十位 Team ID 用于 `APPLE_TEAM_ID`。Team ID 也可从 Apple Developer 账号的 Membership details 页面确认。

## 2. 创建公证凭据

登录 [Apple 账号管理](https://account.apple.com/)，在“登录和安全”中生成一个 App 专用密码，命名例如 `TokChan GitHub notarization`。该账号须可访问相应开发者 Team，并启用双重认证。

本流程使用 Apple ID 和 App 专用密码调用 `notarytool`，不需要 App Store Connect API Key。不要把 Apple 账号的登录密码填入 GitHub。

## 3. 配置 GitHub Secrets

打开仓库 Settings → Secrets and variables → Actions → New repository secret，添加以下六项。

| 名称 | 内容 |
| --- | --- |
| `APPLE_CERTIFICATE_P12_BASE64` | 第一步复制的完整 Base64，必须包含证书及私钥 |
| `APPLE_CERTIFICATE_PASSWORD` | 导出 `.p12` 时设置的密码 |
| `APPLE_SIGNING_IDENTITY` | 完整的 `Developer ID Application: 姓名或组织 (TEAMID)` |
| `APPLE_TEAM_ID` | 十位 Apple Developer Team ID |
| `APPLE_ID` | 用于公证的 Apple 账号邮箱 |
| `APPLE_APP_SPECIFIC_PASSWORD` | 第二步生成的 App 专用密码 |

无需自行添加 `GITHUB_TOKEN`，GitHub Actions 会提供。临时钥匙串密码每次随机生成，也不需要配置。当前应用未启用需要 provisioning profile 的能力，因此本流程不导入描述文件。后续增加相关能力时应重新检查签名配置。

凭据仅注入签名构建步骤。脚本建立独立临时钥匙串，导入证书并保存公证凭据，构建结束或失败时恢复钥匙串搜索列表并清理临时文件。不要将 `.p12`、私钥或密码提交到仓库或贴到 Issue 中。

## 4. Sparkle 更新签名与 feed

使用固定版本 Sparkle 的 `generate_keys` 在受控 Mac 上生成 EdDSA 密钥。私钥只做加密备份，并将其文件内容 base64 编码后保存为 Actions Secret `SPARKLE_PRIVATE_KEY_BASE64`；公钥保存为 Actions Variable `SPARKLE_PUBLIC_ED_KEY`。两者必须配对，私钥不得提交、打印或进入 Release/Pages artifact。

正式流程从已签名、公证并装订票据的同一个 `TokChan.app` 生成仅含应用的 ZIP。CI 先在私有工作区用 Sparkle 官方 `generate_appcast` 生成并验证候选 feed，再把 DMG、SHA-256 与 ZIP 上传到草稿 Release 并逐字节复验。稳定 Release 发布且 ZIP 可公开下载后，才将 `appcast.xml` 与对应发布说明页部署到 `https://youranreus.github.io/TokChan/`。缺少密钥、ZIP、签名字段或 HTTPS 下载地址时流程失败，旧 feed 保持不变。draft、prerelease 与非 `vX.Y.Z` Tag 不进入 feed。若 Release 已发布但 Pages 部署失败，只能重跑同一次 Actions 执行以校验不可变资产并恢复 feed，不得重新上传或改写 Release。

首次启用前必须用隔离 feed 演练两个连续版本，覆盖无更新、断网、无效签名、安装和重启。线上资产出错时不要覆盖 Release 或移动 Tag，应停止推进 feed 并发布新的 patch。EdDSA 与 Developer ID 信任链不要在同一版本同时轮换。

## 5. 本地预检与正式发布

本地无凭据构建保持可用，仅用于开发验证，输出仍是 ad-hoc 签名。

```bash
scripts/build-release.sh --output /tmp/tokchan-local-build
```

在干净且与远端同步的 `master` 分支上，现有发布入口保持不变。

```bash
scripts/release.sh patch --push
```

脚本会本地预检、更新版本并询问创建提交/Tag 以及推送。Tag 推送后，GitHub Actions 才使用 Secrets 重新构建正式公证包。本地预检产物不应作为正式附件手工上传。此文档的命令用于你准备发布时执行；本次流程改造本身不会推送 Tag。

如需在本地测试正式签名，需要在钥匙串中导入证书，并用 `xcrun notarytool store-credentials` 交互式保存凭据，然后设置以下环境变量。

```bash
export APPLE_SIGNING_IDENTITY='Developer ID Application: Your Name (ABCDE12345)'
export APPLE_TEAM_ID='ABCDE12345'
export APPLE_KEYCHAIN_PATH="$HOME/Library/Keychains/login.keychain-db"
export APPLE_NOTARY_PROFILE='tokchan-release'
export SPARKLE_PUBLIC_ED_KEY='generate_keys 输出的公钥'
xcrun notarytool store-credentials "$APPLE_NOTARY_PROFILE" --keychain "$APPLE_KEYCHAIN_PATH"
scripts/build-release.sh --notarize --output /tmp/tokchan-notarized-build
```

正式模式缺少凭据或验证失败会立即报错，不会回退到本地模式。公证服务可能排队，超时后本次构建失败；Actions 失败日志会保留 Apple 返回的详情，先根据日志中的 submission ID 检查状态，解决问题后重新运行同一 Tag 的失败工作流。已发布的 Release 不允许重写。历史流程留下的旧草稿若包含“未公证”说明，需要先检查并更新草稿说明再重试。

## 6. 首次正式发布验收

CI 会校验证书身份、Team ID、嵌套 Sparkle 签名、公证状态、票据、DMG/ZIP 内容、最终校验和、EdDSA appcast 与公私钥配对。Secrets 配置正确并成功跑过真实公证与两版本更新演练之前，不能认为端到端验收已完成。

首次正式包应通过浏览器下载到未安装过 TokChan 的 Mac，保持默认 Gatekeeper 设置，打开 DMG，拖入“应用程序”再启动。确认没有“无法验证开发者”或“Apple 无法检查是否包含恶意软件”的拦截；确认菜单栏、设置和 Tokscale 外部命令正常。另用干净环境在首次启动前断网检查票据可用性，条件允许时分别验证 Apple Silicon 和 Intel。

macOS 仍会执行安全验证，也可能显示正常的“从互联网下载，是否打开”确认。这是系统行为，签名和公证不保证完全无提示。仅允许 App Store 应用的设置或企业设备策略也可能阻止运行。

## 参考

- [Apple Developer ID](https://developer.apple.com/developer-id/)
- [Apple 自定义公证流程](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow)
- [GitHub macOS runner 证书配置](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications)
- [Apple 关于首次打开和 Gatekeeper 的说明](https://support.apple.com/en-us/102445)

# TokChan：Tag 驱动的 macOS 构建与 GitHub Release 方案

> 调研日期：2026-09-04
> 范围：只提供设计，不修改产品构建、发布代码。建议在落地时用当前 GitHub Actions runner 清单和 `xcodebuild -help` 再确认 Xcode/导出参数。

## 1. 结论

推荐采用“两阶段能力、一个发布入口”的方案：

1. **近期先完成可复现的未签名/adhoc 自用包**：本地统一走 `scripts/build-release.sh`；本地版本命令完成 patch 递增、提交和 annotated Tag；推送 `vX.Y.Z` 后，GitHub Actions 在固定 macOS/Xcode 环境中测试、构建 universal app、压缩为 ZIP、生成 SHA-256，并以 draft Release 为事务边界发布。
2. **面向公开用户前升级为 Developer ID 签名与 Apple 公证**：工作流导入 Developer ID Application 证书，启用 Hardened Runtime，导出 distribution-signed app，以 `notarytool` 提交，staple 后重新打包，再发布 GitHub Release。
3. **版本唯一事实源仍是 Xcode 工程的 `MARKETING_VERSION`**；Tag 只是不可变的发布声明，必须严格等于 `v${MARKETING_VERSION}`。`CURRENT_PROJECT_VERSION` 是独立、单调递增的构建号。
4. **不要按 CPU 建两个 Release 包**。当前 app 没有第三方二进制依赖，Release 配置在本机解析为 `arm64 x86_64`；应生成一个 universal `TokChan.app`，在一个 macOS job 内构建和发布，降低矩阵拼装、签名和公证复杂度。

若分发对象只是维护者本人或少量知道如何绕过 Gatekeeper 的可信用户，第一阶段足够。若 GitHub Release 面向普通公众，推荐把 **Developer ID 签名 + 公证设为发布前置条件**，而不是长期发布未签名包。

## 2. 仓库现状与证据

| 项目 | 仓库证据 | 影响 |
|---|---|---|
| 应用类型 | `TokChan.xcodeproj/project.pbxproj` 中 `TokChan` 为 `com.apple.product-type.application`；README 称其为原生 macOS menu-bar app | 产物是 `TokChan.app` |
| 构建入口 | README：`xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build` | 已有 CLI build，但没有归档、打包和发布入口 |
| Scheme | `TokChan.xcodeproj/xcshareddata/xcschemes/TokChan.xcscheme` 已共享；ArchiveAction 使用 Release | CI 可直接引用 `TokChan` scheme |
| 最低系统 | 工程 `MACOSX_DEPLOYMENT_TARGET = 13.0`；README 也写 macOS 13+ | 发布验证至少覆盖 app 元数据和 universal 架构；运行烟测可另行安排 macOS 13 机器 |
| 工具链 | 工程 `objectVersion = 77`、`CreatedOnToolsVersion = 26.0`；本地 `xcodebuild -version` 为 Xcode 26.6 | README 的“Xcode 15+”很可能已经过时；CI 应先固定 Xcode 26 系列并验证，不宜直接依赖漂移的 `macos-latest` |
| 版本号 | app target 的 Debug/Release 都是 `MARKETING_VERSION = 0.1.0`、`CURRENT_PROJECT_VERSION = 1`，且 `GENERATE_INFOPLIST_FILE = YES` | `MARKETING_VERSION` 会进入 `CFBundleShortVersionString`；当前值在 pbxproj 两处，更新必须防止配置漂移 |
| UI 版本 | `TokChan/Features/Settings/SettingsView.swift` 从 `CFBundleShortVersionString` 显示版本 | 构建后可用 `defaults read .../Info.plist CFBundleShortVersionString` 验证 |
| Bundle ID | `com.youranreus.TokChan` | Developer ID、公证和签名验证均以此 app 为对象 |
| 架构 | 当前本机 `xcodebuild -showBuildSettings` 的 Release 为 `ARCHS = arm64 x86_64`、`ONLY_ACTIVE_ARCH = NO` | 可发布单个 universal ZIP；CI 中仍应显式验证 `lipo -archs`，避免 runner 差异造成单架构包 |
| 签名 | `CODE_SIGN_STYLE = Automatic`，无 `DEVELOPMENT_TEAM`；本机解析 `CODE_SIGN_IDENTITY = -`；`ENABLE_HARDENED_RUNTIME = NO` | 当前不具备 Developer ID 公证发布条件；默认构建至多是本机/adhoc 签名语义 |
| Sandbox | README 明确不启用 App Sandbox，因为 Tokscale 需访问本地客户端数据和 LaunchAgent | 直接分发可不启用 Sandbox；这不等于可以不启用 Hardened Runtime，二者需区分 |
| 现有自动化 | 仓库没有 `.github/`，没有 release/build 脚本，当前没有 Git Tag；GitHub API 匿名访问本次返回 403，无法据此确认远端 Releases 状态 | 应按“首个自动发布流程”设计，并在落地时用已认证 `gh` 再盘点远端 Tag/Release |
| 测试 | `TokChanTests`、`TokChanUITests` 均在共享 scheme 的 TestAction 中 | 发布至少运行 unit tests；UI tests 可因 runner GUI 稳定性另设非阻塞或独立 job |

额外注意：当前工作树只有 Trellis 任务目录未跟踪，仓库历史中未发现 release commit/tag 约定。发布脚本必须在执行前要求干净工作树，不能静默把无关修改纳入版本提交。

## 3. 推荐的本地统一入口

### 3.1 命令界面

建议后续新增两个很薄的 shell 入口，而不是要求维护者记忆底层 `xcodebuild`、`ditto`、Git 命令：

```text
scripts/build-release.sh [--configuration Release] [--output dist] [--signing unsigned|developer-id]
scripts/release.sh patch [--push]
```

`build-release.sh` 的职责：

- 默认 `Release`、输出到仓库根的 `dist/`，每次先创建独立临时 DerivedData/Archive 目录。
- 先运行 unit tests，再使用 generic macOS destination 构建或 archive。
- `unsigned` 模式不得依赖登录钥匙串或开发团队；明确设置可复现的签名策略（最终实现时在本机与 runner 上验证选择 `CODE_SIGNING_ALLOWED=NO` 还是显式 adhoc），并把“未 Developer ID 签名、未公证”打印为醒目警告。
- `developer-id` 模式必须检查证书身份、公证凭据和 Hardened Runtime；缺一即失败，绝不能悄悄降级为 adhoc。
- 生成：
  - `dist/TokChan-vX.Y.Z-macos-universal.zip`
  - `dist/TokChan-vX.Y.Z-macos-universal.zip.sha256`
  - 可选保留 `dist/TokChan-vX.Y.Z.xcarchive` 供诊断，但不上传到公开 Release。
- ZIP 使用 Apple 推荐的 `ditto -c -k --keepParent TokChan.app ...`，保留 app bundle 的资源、扩展属性和符号链接。

建议底层构建骨架：

```bash
xcodebuild \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -archivePath "$archive" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  archive
```

正式签名模式随后用 `xcodebuild -exportArchive` 导出 distribution-signed app。具体 `ExportOptions.plist` 的 method/key 必须以落地时固定 Xcode 的 `xcodebuild -help` 为准；Apple 官方明确推荐 Xcode app bundle 采用 archive 后 `-exportArchive`，不要先复制 app 再粗暴执行 `codesign --deep`。

### 3.2 输入校验与失败行为

脚本必须 `set -euo pipefail`，失败时保留或输出日志路径，并且任何一步失败都不得留下一个看似成功的 ZIP。至少检查：

1. 在仓库根执行，存在工程与共享 scheme。
2. `xcodebuild`、`xcrun`、`ditto`、`shasum` 可用；打印 `xcodebuild -version`。
3. 从 Release build settings 读取 `MARKETING_VERSION`，并确认 Debug/Release 中版本一致。
4. 若由 Tag 工作流调用，Tag 满足 `^v[0-9]+\.[0-9]+\.[0-9]+$`，且去掉 `v` 后严格等于 `MARKETING_VERSION`。
5. `CURRENT_PROJECT_VERSION` 为正整数。
6. 构建完成后：
   - `CFBundleShortVersionString == Tag 版本`；
   - `CFBundleVersion == CURRENT_PROJECT_VERSION`；
   - `CFBundleIdentifier == com.youranreus.TokChan`；
   - `lipo -archs TokChan.app/Contents/MacOS/TokChan` 同时含 `arm64`、`x86_64`；
   - 签名模式对应的 `codesign --verify --deep --strict --verbose=2` 成功；
   - 公证模式下 `spctl --assess --type execute --verbose=4` 和 `xcrun stapler validate TokChan.app` 成功。
7. 只有全部验证通过后，才原子移动到 `dist/` 并计算 SHA-256。

本地日常开发 build 可以提供 `--skip-tests`，但 Tag 发布工作流不允许跳过测试与验证。

## 4. 版本递增、提交与 Tag 完整流程

### 4.1 版本规则

- 权威版本：app target 的 `MARKETING_VERSION`，采用 SemVer `X.Y.Z`，不带 `v`。
- Git Tag：`vX.Y.Z`，必须与权威版本一一对应。
- 构建号：`CURRENT_PROJECT_VERSION`，每次发布递增 1；不要用可回退或在 rerun 中变化的 `github.run_number` 覆盖已经由 Tag 指向的源码版本。
- Tag 应使用 annotated tag，并建议维护者配置 Git Tag 签名；工作流无需持有创建 Tag 的凭据。

落地时应把工程设为 Apple Generic Versioning，并用 Xcode 自带 `agvtool` 更新两个 build configuration，避免手写正则误改 pbxproj：

```bash
xcrun agvtool next-version -all
xcrun agvtool new-marketing-version "$next_version"
```

如果实际工程验证发现 `agvtool` 与当前 Xcode 26 工程格式不兼容，则版本脚本必须使用结构化工具或受测试的精确编辑，并在修改后通过 `xcodebuild -showBuildSettings` 验证 Debug/Release 两处值；不能用无约束的全仓库字符串替换。

### 4.2 `scripts/release.sh patch` 应执行的事务

1. `git status --porcelain` 必须为空；当前分支应为默认发布分支，并已与 `origin` 同步。
2. `git fetch origin --tags`；确认当前 HEAD 已推送且不存在目标 Tag/Release。
3. 解析当前 `MARKETING_VERSION=X.Y.Z`，计算 `X.Y.(Z+1)`；拒绝预发布或格式异常值。
4. 将 `CURRENT_PROJECT_VERSION` 加一，将 marketing version 更新为新 patch。
5. 运行版本一致性检查与 `scripts/build-release.sh`（至少 unit tests + Release 构建）。
6. 展示 diff 和将要执行的版本，等待一次明确确认。
7. 创建只包含版本文件的提交：`chore(release): vX.Y.Z`。
8. 创建 annotated tag：`git tag -a vX.Y.Z -m 'TokChan vX.Y.Z'`。
9. 默认停在本地并打印推送命令；只有显式 `--push` 才原子推送 commit 和 tag：

```bash
git push --atomic origin HEAD "refs/tags/vX.Y.Z"
```

`--atomic` 避免只推了 commit 或只推了 Tag。推送前脚本应明确提示：**Tag 是发布触发器，推送后即进入 CI 发布流程**。

### 4.3 本地阶段的恢复

- 版本文件已改、尚未 commit：脚本记录原值；失败时不自动丢弃用户修改，提示 `git diff` 与有针对性的恢复命令。
- 已 commit、尚未 Tag：修复/重跑验证后创建 Tag；若版本提交本身错误且尚未推送，可由维护者 reset/amend。
- 已创建本地 Tag、尚未推送：`git tag -d vX.Y.Z` 后修正；不要复用已公开 Tag。
- commit 已推送、Tag 未推送：修复 CI 前置问题可追加 commit 并重新创建尚未公开的 Tag；不要强推默认分支。
- Tag 已推送：视为不可变。若产物代码有误，发布新的 patch；仅当工作流基础设施临时失败且源码/Tag/预期产物未变时，才 rerun 同一 workflow。

## 5. GitHub Actions 发布设计

### 5.1 触发、权限与并发

建议 `.github/workflows/release.yml` 的核心约束如下：

```yaml
on:
  push:
    tags:
      - 'v[0-9]+.[0-9]+.[0-9]+'

permissions:
  contents: write

concurrency:
  group: release-${{ github.ref }}
  cancel-in-progress: false
```

GitHub 的 tag filter 是 glob，不是完整正则，所以 job 第一条脚本仍须用 regex 严格校验。`contents: write` 是创建 Release 和上传资产所需权限；工作流其余权限保持未授予，并使用仓库自动生成的短期 `GITHUB_TOKEN`，无需个人 PAT。仓库 Settings → Actions → General 还必须允许 workflow 获得 read/write token；组织策略可能覆盖仓库配置。

安全边界：只有受保护的维护者能创建匹配 Tag；建议配置 tag ruleset 保护 `v*`，限制创建/删除/更新。第三方 actions 应固定到完整 commit SHA，避免仅引用可移动 major tag。

### 5.2 Runner、Xcode 与矩阵

- **推荐单 job、单 runner，不设 CPU matrix**：一个 job 产生 universal ZIP，同时避免两个 job 争用同一个 Release。
- 截至调研时 runner-images 官方表显示 `macos-26` 为 arm64、`macos-26-intel` 为 x64；`macos-latest` 会迁移。应选择与 Xcode 26 工程兼容的**固定 OS label**，并显式选择/打印 Xcode 26 路径和版本。
- 初始建议 `runs-on: macos-26`，在该 runner 上显式 `ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO`。若实测 arm runner 无法稳定交叉编译 universal archive，则改为 `macos-26-intel`，仍输出单个 universal 包。
- 不要把 `macos-latest` 和隐含默认 Xcode 当作可复现配置；runner image 每周更新，Xcode patch 更新仍可能发生，因此日志和 Release provenance 中记录 `sw_vers`、`uname -m`、`xcodebuild -version`。

发布 job 顺序：

1. checkout 触发 Tag 指向的 commit（固定 checkout action SHA，`fetch-depth: 0`）。
2. 严格校验 `github.ref_type == tag`、Tag 格式、Tag 版本 == Release `MARKETING_VERSION`、commit 在允许的默认分支历史内（若项目采用只从 main 发布策略）。
3. 运行 unit tests。UI tests 建议先作为独立 CI，而非首版 Release 的硬依赖；稳定后再纳入发布门禁。
4. 导入签名/公证 Secrets（仅 developer-id 阶段），创建临时 keychain，并在 `if: always()` cleanup。
5. 调用与本地完全相同的 `scripts/build-release.sh`，避免本地和 CI 各维护一套构建逻辑。
6. 验证 bundle version、架构、签名、公证，生成 SHA-256。
7. 可选用 `actions/upload-artifact` 保存 ZIP、checksum、公证日志，设置有限 retention，便于失败诊断；这不是最终用户发布入口。
8. 以 draft Release 发布，上传并核验资产，然后转为 published。

### 5.3 Release 资产和行为

Release 名称建议 `TokChan vX.Y.Z`，资产固定为：

```text
TokChan-vX.Y.Z-macos-universal.zip
TokChan-vX.Y.Z-macos-universal.zip.sha256
```

首版可使用 `gh release create "$tag" --verify-tag --draft --generate-notes ...`。`--verify-tag` 防止 CLI 在远端不存在时自动创建 Tag；源码归档由 GitHub 自动提供，用户安装应选择明确命名的 app ZIP。

推荐的防重复/可恢复状态机：

1. `gh release view "$tag" --json isDraft`。
2. 若不存在，创建 draft。
3. 若存在且 `isDraft=true`，认为是同一 Tag 的失败重试：使用 `gh release upload "$tag" ... --clobber` 替换同名资产，再校验资产名/数量。
4. 若已经 published，**立即失败，不覆盖**。已发布资产应视为不可变；若仓库启用了 immutable releases，发布后也会阻止替换/删除资产和移动 Tag。
5. 所有资产上传且 checksum 验证成功后，执行 `gh release edit "$tag" --draft=false --latest`。

这比直接 `gh release create tag files...` 更安全：中途失败时用户不会看到缺资产的正式 Release，rerun 又能复用 draft。`concurrency` 防止同一 Tag 的两个 run 同时修改 draft。工作流不应在失败时自动删远端 Tag，也不应自动删除 published Release。

## 6. 签名、公证与 Secrets

### 6.1 三种分发等级

| 等级 | 做法 | 用户体验与适用范围 |
|---|---|---|
| 本地开发 | Apple Development 或 Xcode 管理签名 | 仅开发机器，不作为 Release |
| 未签名/adhoc ZIP | 明确标注未签名、未公证；Release notes 给出校验 checksum 和风险提示 | 仅个人自用或小范围可信用户；下载后 Gatekeeper 可能阻止/强警告，不建议面向普通公众 |
| Developer ID + notarization | Developer ID Application、secure timestamp、Hardened Runtime、`notarytool`、staple | GitHub 直接公开分发的推荐方案 |

Apple 明确要求 Developer ID 公证软件具备有效签名、Developer ID 证书、Hardened Runtime 和 secure timestamp。当前工程 `ENABLE_HARDENED_RUNTIME = NO`，因此签名阶段落地前必须先启用并回归测试。TokChan 不启用 App Sandbox 与 Hardened Runtime 并不冲突。

### 6.2 推荐 Secrets

**代码签名：**

- `MACOS_CERTIFICATE_P12_BASE64`：只包含 Developer ID Application 私钥和证书的 `.p12`，base64 后存储。
- `MACOS_CERTIFICATE_PASSWORD`：P12 密码。
- `KEYCHAIN_PASSWORD`：CI 临时 keychain 的随机强密码（也可每次运行生成，不必长期保存）。
- `APPLE_TEAM_ID`：可使用 repository variable；不是机密，但需准确。

工作流将 P12 解码到临时文件，创建临时 keychain，`security import`，设置 key partition list，仅在当前 job 使用，结束后删除文件和 keychain。日志中不得打印 secret 或完整私钥。证书应定期轮换，并记录到期日。

**公证，优先 App Store Connect API key：**

- `ASC_KEY_ID`
- `ASC_ISSUER_ID`
- `ASC_PRIVATE_KEY_P8_BASE64`

调用形态：`xcrun notarytool submit <zip-or-dmg> --key <path> --key-id ... --issuer ... --wait`。API key 比维护者 Apple ID 密码更适合自动化和撤销。

备选 Apple ID 方式：

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_APP_SPECIFIC_PASSWORD`

调用 `notarytool --apple-id --team-id --password`。Apple 2FA 账户需 app-specific password。Apple 官方还支持先用 `notarytool store-credentials` 写入 keychain profile；CI 中无论哪种方式都应使用临时 keychain，不能把明文凭据写入仓库。

### 6.3 公证顺序

1. 用 Xcode archive + export 产生 Developer ID distribution-signed app。
2. `codesign --verify --deep --strict --verbose=2 TokChan.app`。
3. 以 `ditto -c -k --keepParent` 生成提交给 notary service 的 ZIP。
4. `xcrun notarytool submit ... --wait`；记录 submission ID。
5. 无论成功与否下载/保存 notary log；Apple 建议成功也检查 warnings。
6. 对 **app bundle** 执行 `xcrun stapler staple` 和 `stapler validate`。ZIP 本身不能 staple。
7. 对已 staple 的 app **重新创建最终 ZIP**。
8. `spctl --assess --type execute --verbose=4 TokChan.app`，再生成 checksum 和 Release。

公证失败时保存 submission ID 和 JSON log 为 workflow artifact，不创建/发布正式 Release。网络超时但 submission 已接收时，可用同一 ID 执行 `notarytool info`/`log` 判断结果，不要盲目重复提交。

## 7. 失败恢复、重复发布和回滚

| 场景 | 恢复动作 |
|---|---|
| 测试/构建失败，尚无 Release | 修复 workflow 或代码。若仅基础设施问题可 rerun；若源码需改，发布新 patch Tag |
| 公证返回 Invalid | 下载 notary log，修复签名/Hardened Runtime 后发布新 patch；不要用同一公开 Tag 指向新 commit |
| 公证超时 | 从日志/artifact 找 submission ID，用 `notarytool info` 和 `log` 续查；确认未完成前不重复提交 |
| draft 创建后资产上传失败 | rerun 同一 workflow，识别 draft，`gh release upload --clobber` 后再发布 |
| Release 已发布后 workflow 被 rerun | 检测到 published 后失败；不替换资产 |
| 错误 Tag 已推送、尚未发布 | 维护者可删除远端 Tag 后创建正确 Tag，但要先确认没有用户消费；更稳妥仍是新 patch |
| 错误二进制已公开 | 不覆盖同名资产、不移动 Tag；将 Release 标记/说明为有问题，必要时删除公开 Release，并发布修复 patch。若证书泄露，同时撤销证书并联系 Apple 处理 notarization tickets |
| GitHub Release API 临时故障 | 构建 artifact 有限期保留；rerun 使用 draft 恢复，不重建不同内容后覆盖已发布资产 |

所谓“回滚”不应把版本号倒退，也不应把 `vX.Y.Z` 强制移动到旧 commit。桌面 app 发布的安全恢复单位是一个新的 patch 版本。

## 8. 分阶段落地清单

### Phase 0：确认分发策略

- [ ] 明确个人自用、小范围可信用户或公开用户。
- [ ] 公开用户则确认 Apple Developer Program 团队、Developer ID Application 证书与公证 API key 的负责人。
- [ ] 校正 README 的 Xcode 最低版本；以能读取 objectVersion 77 且通过构建的版本为准。

### Phase 1：统一本地构建

- [ ] 新增 `scripts/build-release.sh`，实现测试、Release archive/build、universal 校验、ZIP、checksum。
- [ ] 固定输出命名与失败行为。
- [ ] 在 Intel 和 Apple Silicon 真机分别解压和启动测试。
- [ ] 将 `dist/` 加入 ignore（落地任务执行，不在本调研修改）。

### Phase 2：版本与本地发布命令

- [ ] 配置/验证 Apple Generic Versioning。
- [ ] 新增 `scripts/release.sh patch`，实现干净树、同步、patch/build-number 更新、验证、commit、annotated Tag、可选 atomic push。
- [ ] 为 SemVer 解析、两个 build configuration 一致性和重复 Tag 写脚本级测试。

### Phase 3：GitHub draft Release

- [ ] 新增 tag workflow，严格 regex 与版本一致性校验。
- [ ] 固定 macOS runner label 和 Xcode 26；actions 固定完整 SHA。
- [ ] 最小权限 `contents: write`，同 Tag concurrency。
- [ ] draft → upload/verify → publish；published Release 禁止覆盖。
- [ ] 配置 `v*` tag ruleset，并用一次测试版本验证失败重试。

### Phase 4：公开分发加固

- [ ] 启用 Hardened Runtime，确认 app 调用 `npx`、读取本地 Tokscale 数据、操作 LaunchAgent 的行为不受影响。
- [ ] 配置 Developer ID 和 ASC API key Secrets。
- [ ] 实现 archive/export/sign/notarytool/staple/spctl 全链路。
- [ ] 开启或评估 GitHub immutable releases。
- [ ] 制定证书轮换、泄露与 Apple ticket 撤销联系人流程。

## 9. 验证命令清单

```bash
# 工具链和工程
xcodebuild -version
xcodebuild -list -project TokChan.xcodeproj
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Release -showBuildSettings \
  | grep -E 'MARKETING_VERSION|CURRENT_PROJECT_VERSION|ARCHS|ENABLE_HARDENED_RUNTIME|CODE_SIGN'

# 测试
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'

# Bundle 元数据
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' TokChan.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' TokChan.app/Contents/Info.plist
/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' TokChan.app/Contents/Info.plist

# 架构
lipo -archs TokChan.app/Contents/MacOS/TokChan

# 签名与 Gatekeeper
codesign --verify --deep --strict --verbose=2 TokChan.app
codesign -dvvv TokChan.app
spctl --assess --type execute --verbose=4 TokChan.app

# 公证票据
xcrun stapler validate TokChan.app
xcrun notarytool info "$SUBMISSION_ID" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER_ID"
xcrun notarytool log "$SUBMISSION_ID" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER_ID" notary-log.json

# 资产完整性
shasum -a 256 TokChan-vX.Y.Z-macos-universal.zip
unzip -t TokChan-vX.Y.Z-macos-universal.zip

# 远端 Tag 和 Release
git ls-remote --tags origin 'vX.Y.Z'
gh release view vX.Y.Z --json tagName,isDraft,isPrerelease,url,assets
```

## 10. 主要取舍

- **ZIP 而非 DMG**：ZIP 可由 `ditto` 简单、可靠地保留 app bundle，Apple notary service 接受 ZIP；首版不需要维护 DMG 布局和签名。若未来需要拖拽安装界面，再新增 notarized DMG。
- **一个 universal 包而非双架构矩阵**：用户选择成本更低，Release 原子性更简单，签名/公证只做一次。若未来引入仅单架构的二进制依赖，再重新评估矩阵。
- **版本在源码中提交，而非 CI 动态注入**：About 页、Tag、源码和可复现构建天然一致；代价是每次 release 有一个版本提交。
- **draft 事务而非直接发布**：多一步 API 操作，但显著降低半成品 Release 和 rerun 覆盖风险。
- **公开发布必须签名/公证**：增加 Apple Developer 凭据维护成本，但换来正常 Gatekeeper 体验和可审计身份。未签名仅是明确受限的过渡模式。

## 11. 官方资料

### Apple

- [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) — Developer ID、公证要求、Hardened Runtime、secure timestamp、ticket/stapling。
- [Creating distribution-signed code for macOS](https://developer.apple.com/documentation/xcode/creating-distribution-signed-code-for-the-mac) — Xcode app 应 archive 后 export；Developer ID identity；签名顺序；反对用 `codesign --deep` 代替正确签名流程。
- [Customizing the notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow) — `xcodebuild -exportArchive`、`ditto` ZIP、`notarytool submit --wait`、日志与 staple；ZIP 不能直接 staple。
- [TN3147: Migrating to the latest notarization tool](https://developer.apple.com/documentation/technotes/tn3147-migrating-to-the-latest-notarization-tool) — `notarytool` 凭据方式、API key/app-specific password、history/info/log；`altool` 公证已弃用。
- [Distributing your app for beta testing and releases](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases) — Xcode 分发入口与渠道背景。

### GitHub Actions 与 Releases

- [Workflow syntax for GitHub Actions](https://docs.github.com/en/actions/writing-workflows/workflow-syntax-for-github-actions) — tag filters、permissions、concurrency 等 workflow 语义。
- [Use GITHUB_TOKEN for authentication in workflows](https://docs.github.com/en/actions/security-for-github-actions/security-guides/automatic-token-authentication) — 自动 token 与最小权限。
- [Choosing the runner for a job](https://docs.github.com/en/actions/using-jobs/choosing-the-runner-for-a-job) — hosted runner 选择。
- [actions/runner-images supported images](https://github.com/actions/runner-images#available-images) — 当前 macOS label、CPU 架构和 `-latest` 迁移策略；runner 内容会持续更新。
- [Managing releases in a repository](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository) — draft、发布、编辑/删除与 immutable releases 行为。
- [Immutable releases](https://docs.github.com/en/code-security/concepts/supply-chain-security/immutable-releases) — 发布后资产和 Tag 的不可变保护。

### GitHub CLI

- [`gh release create`](https://cli.github.com/manual/gh_release_create) — `--verify-tag`、`--draft`、`--generate-notes` 和资产上传。
- [`gh release view`](https://cli.github.com/manual/gh_release_view) — 发布前重复检测和 JSON 状态读取。
- [`gh release upload`](https://cli.github.com/manual/gh_release_upload) — draft 重试时用 `--clobber` 替换同名资产。
- [`gh release edit`](https://cli.github.com/manual/gh_release_edit) — draft 验证完成后发布。
- [`gh release delete`](https://cli.github.com/manual/gh_release_delete) — 人工事故恢复；不应成为工作流正常路径。

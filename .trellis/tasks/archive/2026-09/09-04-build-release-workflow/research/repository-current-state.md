# 仓库当前构建与版本机制调研

## 范围与结论摘要

本报告只描述当前仓库事实，不提出完整的目标发布方案。

TokChan 当前是一个原生 SwiftUI macOS 菜单栏应用，由单一 Xcode project 和共享 scheme 构建。仓库已有可用的 `xcodebuild ... build` 开发构建入口，但没有统一的本地构建/打包脚本，也没有版本递增脚本、归档导出配置、签名凭据配置、公证流程、GitHub Actions 或 GitHub Release 自动化。当前可直接得到的产品是 `TokChan.app`；仓库没有定义 DMG、PKG 或 ZIP 发布产物。

版本号的仓库权威来源是 `TokChan.xcodeproj/project.pbxproj` 中 TokChan target 的 `MARKETING_VERSION = 0.1.0` 与 `CURRENT_PROJECT_VERSION = 1`。两者分别存在于 Debug 和 Release 配置中，因此现在存在双点同步风险。应用“关于”界面读取构建生成的 Info.plist 中 `CFBundleShortVersionString`，没有另设版本常量。

签名方面，各 target 只声明 `CODE_SIGN_STYLE = Automatic`，没有提交 `DEVELOPMENT_TEAM`、签名 identity、provisioning profile、entitlements 或 ExportOptions。有效 Release 设置显示 signing required/allowed，但 identity 为 `-`，App Sandbox 与 Hardened Runtime 均关闭。由此可支持本机/Xcode 默认签名或 ad-hoc 风格的开发产物，但仓库本身不足以复现面向外部分发的 Developer ID 签名与 Apple 公证。

## 1. 应用与工程类型

### 1.1 原生 macOS SwiftUI 菜单栏应用

- `TokChan/TokChanApp.swift:1-4` 导入 SwiftUI，并以 `@main struct TokChanApp: App` 作为应用入口。
- `TokChan/TokChanApp.swift:47-57` 使用 `MenuBarExtra` 和 `Settings` scene，确认它是菜单栏应用，而非命令行工具、Web 应用或跨平台包装应用。
- `README.md:3` 将项目描述为 native macOS menu-bar companion。
- `README.md:7-10` 声明运行要求为 macOS 13+、Xcode 15+、Node.js/`npx` 以及 Tokscale 登录。
- `README.md:20` 明确应用不创建 Dock 图标。
- `TokChan.xcodeproj/project.pbxproj:213-214` 和 `:233-234` 将 `LSApplicationCategoryType` 设为 developer tools，并将 `LSUIElement` 设为 `YES`，这与 agent/menu-bar app 行为一致。

### 1.2 单一 Xcode project，无 Swift Package 依赖

- 主工程文件为 `TokChan.xcodeproj/project.pbxproj`；仓库不存在 workspace 或 `Package.swift`。
- `TokChan.xcodeproj/project.pbxproj:67-118` 定义 3 个 native target：
  - `TokChan`，产品类型 `com.apple.product-type.application`（`:68-84`）；
  - `TokChanTests`，unit-test bundle（`:85-101`）；
  - `TokChanUITests`，UI-testing bundle（`:102-118`）。
- `TokChan.xcodeproj/project.pbxproj:78-80` 显示应用 target 使用 file-system-synchronized source group，且 `packageProductDependencies = ()`。
- 全文件不存在 `XCRemoteSwiftPackageReference`、`XCSwiftPackageProductDependency` 或 `PBXShellScriptBuildPhase`。因此当前工程没有 SwiftPM 依赖，也没有 Xcode build phase 内置的构建/发布 shell 脚本。

## 2. 构建入口、scheme 与 configuration

### 2.1 当前公开构建入口

README 给出的唯一产品构建命令是：

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS' build
```

证据：`README.md:12-18`。同一位置也说明可在 Xcode 中打开 `TokChan.xcodeproj` 并运行 `TokChan` scheme（`:14`）。

仓库根目录没有 `Makefile`、`Justfile`、`Package.swift`、`.sh`、`.command` 或产品侧 YAML 脚本；Git 树中也没有 `scripts/`、`bin/` 或 `.github/` 文件。因此维护者目前必须直接记忆/调用 `xcodebuild`。

### 2.2 Scheme

共享 scheme 位于 `TokChan.xcodeproj/xcshareddata/xcschemes/TokChan.xcscheme`，因此命令行和 CI checkout 均可发现它。

- `TokChan.xcodeproj/xcshareddata/xcschemes/TokChan.xcscheme:5-10`：BuildAction 只构建 `TokChan.app`，并允许 testing、running、profiling、archiving 和 analyzing。
- 同文件 `:12-21`：TestAction 使用 Debug configuration，并包含 `TokChanTests` 与 `TokChanUITests`。
- 同文件 `:22-26`：LaunchAction 使用 Debug。
- 同文件 `:27-31`：ProfileAction 使用 Release。
- 同文件 `:32`：AnalyzeAction 使用 Debug。
- 同文件 `:33`：ArchiveAction 使用 Release。

本机执行 `xcodebuild -project TokChan.xcodeproj -list` 也只列出一个 `TokChan` scheme、`TokChan`/`TokChanTests`/`TokChanUITests` 三个 target，以及 Debug/Release 两个 configuration。命令同时报告本机 CoreSimulator framework 与 Xcode 版本不匹配；这不影响 project 元数据读取，但提示本机 UI/simulator 测试环境另有风险。

### 2.3 Build configurations 与平台

- project-level Debug 配置位于 `TokChan.xcodeproj/project.pbxproj:170-189`；Release 位于 `:190-204`。
- `TokChan.xcodeproj/project.pbxproj:302-305` 显示 project 和三个 target 均具有 Debug、Release，且未显式指定配置时默认 Release。
- `TokChan.xcodeproj/project.pbxproj:182-184` 与 `:199-200` 指定 macOS 13.0 deployment target 和 `macosx` SDK。
- app target 的 Debug/Release 设置分别位于 `TokChan.xcodeproj/project.pbxproj:205-224` 和 `:225-244`。
- README 的 macOS 13+ 要求与工程设置一致，见 `README.md:7`。

使用当前本机 Xcode 26.6 执行 Release `-showBuildSettings`，有效设置包括：

- `ARCHS = arm64 x86_64`；
- `MACOSX_DEPLOYMENT_TARGET = 13.0`；
- `FULL_PRODUCT_NAME = TokChan.app`；
- `WRAPPER_EXTENSION = app`；
- 默认 `CONFIGURATION_BUILD_DIR` 为 DerivedData 下的 `Build/Products/Release`。

这意味着当前通用 macOS Release 构建解析为 arm64+x86_64 的 `.app` bundle；不过仓库没有脚本固定 `-derivedDataPath` 或输出目录，默认产物位置因机器和 DerivedData 状态而异。

## 3. 产物格式与归档现状

### 3.1 当前直接产品

- `TokChan.xcodeproj/project.pbxproj:26-30` 定义构建产品 `TokChan.app`、`TokChanTests.xctest` 和 `TokChanUITests.xctest`。
- `TokChan.xcodeproj/project.pbxproj:81-84` 将主产品绑定为 `TokChan.app` application wrapper。
- shared scheme 的 ArchiveAction 可做 Release archive，见 `TokChan.xcodeproj/xcshareddata/xcschemes/TokChan.xcscheme:33`。

因此当前最明确的可分发候选是 Release `TokChan.app`。普通 `build` 不会自动产生 `.xcarchive`；需要另行执行 `xcodebuild archive`。仓库虽允许 archive，却没有记录 archive 命令、`archivePath`、导出步骤或发布附件命名约定。

### 3.2 尚未定义的发布格式

全仓产品文件中没有：

- `ExportOptions.plist`；
- DMG/PKG 创建配置；
- ZIP 打包命令；
- Sparkle/appcast 或其他自动更新配置；
- release notes/changelog 生成脚本。

所以目前不能从仓库推导出 DMG、PKG 或 ZIP 哪一个是正式发布格式，也没有稳定、可上传 GitHub Release 的文件名和校验文件。

## 4. 版本号权威来源与消费路径

### 4.1 权威写入点

TokChan app target 的两个配置均直接在 Xcode project 文件内声明版本：

- Debug：`CURRENT_PROJECT_VERSION = 1`，见 `TokChan.xcodeproj/project.pbxproj:211`；`MARKETING_VERSION = 0.1.0`，见 `:216`。
- Release：`CURRENT_PROJECT_VERSION = 1`，见 `TokChan.xcodeproj/project.pbxproj:231`；`MARKETING_VERSION = 0.1.0`，见 `:236`。

仓库不存在 `Info.plist` 或 `.xcconfig` 版本文件，也不存在 `Package.swift`/package manifest。故当前仓库中的权威来源只能认定为上述 project build settings：

- 用户可见版本：`MARKETING_VERSION`，当前 `0.1.0`；
- 构建号：`CURRENT_PROJECT_VERSION`，当前 `1`。

风险是 Debug/Release 各自保存了一份相同值。手工 patch 更新若只修改一处，会产生 configuration 间漂移。

### 4.2 Info.plist 生成与 UI 展示

- `TokChan.xcodeproj/project.pbxproj:212`、`:232` 设置 `GENERATE_INFOPLIST_FILE = YES`，故 Info.plist 是 Xcode 构建生成的，不是仓库中的独立源文件。
- `TokChan/Features/Settings/SettingsView.swift:191-192` 在关于界面展示 `appVersion`。
- `TokChan/Features/Settings/SettingsView.swift:203-205` 从 `Bundle.main.infoDictionary["CFBundleShortVersionString"]` 读取版本，失败时显示“未知”。

按 Xcode build-setting 映射，生成的 `CFBundleShortVersionString` 来自 `MARKETING_VERSION`，`CFBundleVersion` 来自 `CURRENT_PROJECT_VERSION`。应用代码没有硬编码第二份用户可见版本值。

### 4.3 当前没有版本发布历史机制

在调研时：

- `git tag --list` 无输出，仓库尚无 Git Tag；
- Git remote 为 `git@github.com:youranreus/TokChan.git`；
- 默认分支/当前分支为 `master`，远端跟踪为 `origin/master`；
- Git 历史没有可识别的 release/version bump 提交惯例；
- 仓库没有 patch bump、commit、tag 或 push 脚本。

因此当前没有可复用的 Tag 格式（例如 `v0.1.0`）、Tag 与 `MARKETING_VERSION` 一致性校验、构建号递增规则或重复版本保护。

## 5. 签名、Sandbox、Hardened Runtime 与公证

### 5.1 已提交的签名配置

- TokChan Debug/Release 均为 `CODE_SIGN_STYLE = Automatic`，见 `TokChan.xcodeproj/project.pbxproj:209`、`:229`。
- unit-test target 同样为 Automatic，见 `:249`、`:263`。
- UI-test target同样为 Automatic，见 `:276`、`:289`。
- project 文件没有 `DEVELOPMENT_TEAM`、`CODE_SIGN_IDENTITY`、`PROVISIONING_PROFILE_SPECIFIER`、`CODE_SIGN_ENTITLEMENTS` 或 `SystemCapabilities` 条目。
- 仓库没有 `.entitlements` 文件。

在未强制关闭签名的 Release `-showBuildSettings` 查询中，有效值为：

```text
CODE_SIGNING_ALLOWED = YES
CODE_SIGNING_REQUIRED = YES
CODE_SIGN_IDENTITY = -
CODE_SIGN_STYLE = Automatic
ENABLE_APP_SANDBOX = NO
ENABLE_HARDENED_RUNTIME = NO
```

没有解析出 `DEVELOPMENT_TEAM` 或 Developer ID identity。`CODE_SIGN_IDENTITY = -` 不能视为已配置 Developer ID 分发签名。

### 5.2 Sandbox 是刻意关闭的

- `README.md:33` 明确说明应用故意不启用 App Sandbox，因为 Tokscale 需要访问本地 client data，并管理自己的 macOS LaunchAgent。
- 有效构建设置也显示 `ENABLE_APP_SANDBOX = NO`。

这意味着当前产品不适合直接假设走 Mac App Store sandbox 分发；发布设计应以站外分发约束评估签名和公证。

### 5.3 Hardened Runtime 与公证均未配置

- project 文件没有 `ENABLE_HARDENED_RUNTIME`；有效 Release 设置为 `NO`。
- 仓库没有 `notarytool`、`altool`、`stapler`、`codesign`、Developer ID、Apple ID、App Store Connect API key 或 keychain profile 的产品发布配置/脚本。
- 仓库没有签名证书导入、临时 keychain 创建或 CI secret 名称约定。

结论：当前仓库没有 Apple 公证流程。若目标是公开站外分发，现状缺少至少 Hardened Runtime、Developer ID Application 签名、notary submission、等待结果与 stapling；若仅给受信任的小范围用户，则可以接受更低配置，但 Gatekeeper 体验和风险必须另行说明。

## 6. 已有脚本与 GitHub 自动化

### 6.1 产品构建/版本脚本

除 README 的单条 `xcodebuild` 命令外，没有产品构建发布脚本。Xcode project 也没有 Shell Script build phase。Trellis 目录下存在项目管理脚本，但它们只管理开发任务与会话，不是 TokChan 的产品 build/version/release 入口，不能算已有发布机制。

### 6.2 GitHub Actions / Release

Git 当前树不存在 `.github/` 目录，因此没有：

- push/tag trigger；
- CI build/test job；
- macOS runner/Xcode 版本选择；
- artifact upload；
- GitHub Release 创建；
- release permissions；
- signing/notarization secrets；
- concurrency 或重复发布保护。

仓库 remote 已指向 GitHub，故未来可以引入 GitHub Actions，但当前没有任何可继承 workflow。

## 7. 当前机制的可复现性与主要缺口

| 方面 | 当前事实 | 直接后果 |
| --- | --- | --- |
| 工程入口 | `TokChan.xcodeproj` + shared `TokChan` scheme | CLI/CI 可发现，基础较好 |
| 构建命令 | README 仅给普通 `xcodebuild ... build` | 无统一参数、输出目录和失败封装 |
| Configuration | Debug/Release；ArchiveAction 用 Release | 可做 Release/archive，但尚无正式命令 |
| 最低系统 | macOS 13.0 | README 与 project 一致 |
| 架构 | 通用 macOS Release 查询为 arm64+x86_64 | 当前可形成 universal app；应在发布脚本中验证 |
| 直接产物 | `TokChan.app` | 没有定义 GitHub Release 附件封装格式 |
| 用户版本 | project 内两份 `MARKETING_VERSION = 0.1.0` | patch bump 必须同步 Debug/Release |
| 构建号 | project 内两份 `CURRENT_PROJECT_VERSION = 1` | 尚无递增或与 Tag 关联规则 |
| Info.plist | Xcode 自动生成 | 不应再创建第二份版本真相源 |
| 签名 | Automatic，但无 Team/Developer ID | checkout 不能独立复现外部分发签名 |
| Sandbox | 关闭，且 README 说明是刻意设计 | 不宜按 Mac App Store 路径设计 |
| Hardened Runtime | 有效值为 NO | 不满足常规 Developer ID 公证基线 |
| 公证 | 无 | 公开分发会面临 Gatekeeper 风险 |
| 本地发布脚本 | 无 | 维护者需记忆多条底层命令 |
| Git Tag | 无历史 Tag/规范 | 尚无版本到发布触发器的约定 |
| GitHub Actions | 无 `.github/` | 目前不会自动构建或创建 Release |

## 8. 后续设计必须显式决定的问题

这些不是当前仓库已有机制，而是由现状暴露出的设计输入：

1. **发布受众**：私用/小范围可信用户还是公开下载。它决定 Developer ID、公证和凭据投入是否列为首版硬要求。
2. **正式附件格式**：直接 ZIP 包装 `.app`、DMG，还是其他格式。当前仓库没有既定答案；ZIP 通常维护成本最低，但需在方案阶段确认。
3. **版本与构建号规则**：patch 时仅把 `0.1.0` 改为 `0.1.1`，还是同时递增 build number；需避免 Debug/Release 双点漏改。
4. **Tag 规范**：建议方案需要选择并校验类似 `v<MARKETING_VERSION>` 的唯一形式，因为当前无历史兼容负担。
5. **本地与 CI 的构建一致性**：需要固定 scheme、Release、destination、DerivedData/output 路径，并决定 test 是否为 release 前置条件。
6. **签名职责边界**：无签名构建、ad-hoc 构建和 Developer ID 构建应明确区分，不应让成功生成 `.app` 被误认为已可公开分发。
7. **CI 权限与凭据**：创建 GitHub Release 至少需要 workflow `contents: write`；若加入公证，还需定义证书、私钥、Team ID 与 notary 凭据的 secret 管理方式。
8. **失败与重跑语义**：Tag 已推送但 build/release 失败时，是修复后 rerun 原 workflow，还是删除/重建 Tag；已有 Release/asset 时是否覆盖。当前仓库没有保护机制。

## 9. 调研方法与证据边界

本报告使用以下只读检查：

- 读取 `README.md`、SwiftUI app 入口、Settings 版本展示、Xcode project 与 shared scheme；
- 通过 `git ls-files` 与文件名搜索检查脚本、workflow、plist、xcconfig、entitlements 和 packaging 文件是否存在；
- 通过关键词搜索检查版本、签名、公证和 release 配置；
- 执行 `xcodebuild -project TokChan.xcodeproj -list`；
- 执行 Release `-showBuildSettings`（分别查询默认签名设置，以及用 `CODE_SIGNING_ALLOWED=NO` 做不依赖签名身份的元数据查询）；
- 查询 Git remote、Tag 和近期历史。

“没有”类结论限于本次 checkout 的 tracked product tree 与可见工作树。调研没有执行 build/archive、没有访问开发者证书或 GitHub 仓库 Settings/Secrets，也没有修改任何产品代码或配置。本机命令环境为 Xcode 26.6（build 17F113）；该版本高于 `README.md:8` 声明的最低 Xcode 15。

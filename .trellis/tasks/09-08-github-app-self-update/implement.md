# GitHub 应用内自更新实施计划

## 变更边界

最小行为缺口是已安装应用无法主动发现和安装后续版本。该行为横跨应用生命周期、设置 UI 和 Release 产物，必须同时接入 Sparkle、提供手动入口，并让发布流程产出受信任的 feed/更新归档。

预计修改范围：

- `TokChan.xcodeproj/project.pbxproj`、`TokChan/SupportingFiles/Info.plist`：固定 Sparkle Swift Package、链接 product，并写入 updater 所需 Info.plist 配置与 build setting 展开值。
- `TokChan/TokChanApp.swift`：创建长生命周期 updater controller/适配器并注入设置页；UI test 注入离线替身。
- `TokChan/Features/Settings/SettingsView.swift`：关于页增加“检查更新”按钮并绑定可用状态。
- `TokChan/Shared/Services/`：新增窄 updater 协议与 Sparkle 适配层，隔离第三方框架和测试替身。
- `TokChanTests/`、`TokChanUITests/`：覆盖适配器/按钮接线和无网络 UI 行为。
- `scripts/build-release.sh`、`scripts/ci-build-release.sh`、`.github/workflows/release.yml`：生成并验证更新 ZIP、签名/appcast，并按安全顺序发布。
- `tests/test_release_scripts.sh`：覆盖发布契约与失败关闭。
- `docs/macos-release.md`、`README.md`：记录 EdDSA 密钥、feed 托管、发布和用户入口。

明确不做自动/定时检查、自定义更新窗口、预发布通道、自研应用替换器，也不改变现有 DMG 首次安装流程。

## 实施步骤

### 1. 固定依赖与配置

- [x] 选择支持 macOS 13 的稳定 Sparkle 2 版本并在 Xcode 工程中固定精确版本/受控版本范围。
- [x] 将 `Sparkle` product 只链接到应用 target，确认测试 target 可通过应用模块或替身测试而无需发起网络。
- [x] 添加 HTTPS `SUFeedURL`、`SUPublicEDKey` 和禁用自动检查的配置。
- [x] 构建后检查生成的 Info.plist 和应用签名，确认配置存在且无私钥材料。

回滚点：依赖和 build settings 应形成独立可还原改动；若 Sparkle 与 macOS 13 或当前签名流程不兼容，在进入 UI/发布改造前停止。

### 2. 建立 updater 边界

- [x] 定义最小 `AppUpdating` 协议和可观察的 `canCheckForUpdates` 状态。
- [x] 用 `SPUStandardUpdaterController` 实现 live adapter，控制器在应用生命周期内保持强引用。
- [x] 为 Preview/UI tests 提供完全离线的 updater 替身。
- [x] 在 `TokChanApplicationDelegate`/`TokChanApp` 组合根创建并向 `SettingsView` 注入依赖。
- [x] 单元测试动作只转发一次、忙碌状态禁止重复动作、状态恢复后重新可用。

回滚点：第三方类型只留在适配层和组合根；若 API 形态需调整，不扩散进 `SettingsView`。

### 3. 添加关于页入口

- [x] 在关于页内容底部加入“检查更新”按钮，保持现有原生 SwiftUI Settings 布局与可访问性标识。
- [x] 按钮触发显式用户检查并使用 `canCheckForUpdates` 控制禁用状态。
- [x] 更新 UI fixture 和 UI tests，验证按钮存在、点击调用替身且测试不访问网络。
- [ ] 人工验证 Sparkle 标准窗口在无更新、新版、下载中和错误状态下的交互。

### 4. 扩展正式发布产物

- [x] 从已完成 Developer ID 签名、公证和票据装订的同一 `TokChan.app` 生成只含应用的 universal 更新 ZIP。
- [x] 对 ZIP 内容、架构、bundle 版本、代码签名、公证票据和不可覆写行为执行本地校验。
- [x] 在正式 CI 中从受保护 secret/key material 加载 EdDSA 私钥；缺失或无效时 fail closed。
- [x] 使用固定 Sparkle 工具版本生成签名和 appcast；确保 feed 只含稳定已发布版本。
- [x] Release 上传 DMG、DMG SHA-256 和更新 ZIP；发布说明继续由 GitHub Release 维护。
- [x] 将 appcast/发布说明部署到固定 HTTPS GitHub 托管地址，并保证 feed 是最后发布的原子发现点。
- [x] 重跑/已存在 Release 路径不得覆盖公开资产或让 feed 指向不完整版本。

回滚点：在 feed 推进前，额外 ZIP/草稿资产不会被客户端发现；失败时保留旧 feed。

### 5. 自动化验证与文档

- [x] 为 shell fixture 增加 Sparkle 工具、密钥、ZIP、appcast 和发布顺序场景。
- [x] 验证正常路径以及缺密钥、签名失败、错误 URL、缺资产、draft/prerelease、重复发布等失败路径。
- [x] 更新发布文档，说明 EdDSA 私钥保管/轮换、feed URL 稳定性、部署顺序、故障回滚与端到端演练。
- [x] 更新 README 的应用内检查入口，同时保留 DMG 手工安装/恢复说明。

### 6. 端到端发布门禁

- [ ] 使用隔离测试 feed 和两个连续测试版本演练旧版到新版的检查、说明、确认、下载、验证、替换与重启。
- [ ] 验证无更新、断网、无效签名和缺失资产不会破坏已安装版本。
- [ ] 在 Apple Silicon 与可用的 Intel 环境验证 universal 更新；至少对最终归档执行双架构静态校验。
- [ ] 测试 feed 通过后再启用正式 feed；首个正式 feed 变更需人工复核 URL、签名、版本和资产下载。

## 验证命令

```bash
# Swift / UI 测试
xcodebuild test -project TokChan.xcodeproj -scheme TokChan -destination 'platform=macOS'

# 发布脚本语法与 fixture
bash -n scripts/build-release.sh scripts/ci-build-release.sh scripts/release.sh tests/test_release_scripts.sh
bash tests/test_release_scripts.sh

# Release 构建（本地无凭据仅验证开发产物；正式 E2E 使用 CI secret）
scripts/build-release.sh

# 最终应用与归档检查（路径按实际版本替换）
codesign --verify --strict --verbose=2 dist/verify/TokChan.app
spctl --assess --type execute --verbose=2 dist/verify/TokChan.app
unzip -l dist/TokChan-v*-macos-universal.zip
curl --fail --silent --show-error '<SUFeedURL>'
```

正式检查还应使用 Sparkle 官方工具验证 appcast/EdDSA 签名，并在下载后的测试更新包上复验 codesign、公证票据、bundle 版本和双架构。

## 启动实现前检查

- [ ] `prd.md`、`design.md` 与本计划一致，没有阻塞性产品决策。
- [ ] 正式 feed 固定为 `https://youranreus.github.io/TokChan/appcast.xml`；明确 EdDSA 公钥，私钥已有安全的 CI 注入与备份方案。
- [ ] 确认选择的 Sparkle 版本/API、许可证与 macOS 13 兼容。
- [ ] `implement.jsonl` 与 `check.jsonl` 均包含真实 spec/research 上下文。
- [ ] 用户已审阅最终规划摘要，并在后续消息明确批准开始实现。

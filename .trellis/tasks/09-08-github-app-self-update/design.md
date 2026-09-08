# GitHub 应用内自更新技术设计

## 1. 设计目标

在不自研高风险应用替换器的前提下，为 TokChan 提供用户主动触发、安全可恢复的应用内更新。首版使用 Sparkle 2 的标准更新窗口和安装链路；GitHub 承担更新 feed 与更新包托管，现有 Developer ID 签名、公证、DMG 和 SHA-256 发布能力继续保留。

## 2. 现状与约束

- TokChan 是 macOS 13+ 的 SwiftUI 菜单栏应用，`SettingsView` 的“关于”页已经展示应用版本。
- Xcode 工程此前没有 Swift Package 依赖；接入后固定 Sparkle 2.7.1。由于 Xcode 自动生成的 Info.plist 不会可靠写入 Sparkle 自定义键，应用改用 `TokChan/SupportingFiles/Info.plist`，并继续通过 build settings 展开版本、公钥等值。
- Release 工作流按 `vX.Y.Z` Tag 构建 universal DMG，完成 Developer ID 签名、公证和票据装订，然后发布 DMG 与 SHA-256。
- 首版只允许手动检查，不执行启动检查、定时检查或后台提醒。
- 私有 EdDSA 密钥不得进入仓库、Release 附件、appcast 或应用包；应用只嵌入公钥。

## 3. 架构边界

### 3.1 Sparkle 集成

- 通过 Swift Package Manager 固定一个经过验证的 Sparkle 2 版本，将 `Sparkle` product 链接到 TokChan target。
- 在应用生命周期根部持有一个长生命周期 `SPUStandardUpdaterController`。它负责 feed 获取、版本比较、标准 UI、下载、EdDSA 验证、安装、失败恢复和重启。
- 向 `SettingsView` 注入一个窄接口，而不是让视图自行创建 updater。接口只暴露：
  - `canCheckForUpdates`：驱动按钮可用性。
  - `checkForUpdates()`：用户动作入口，内部调用 Sparkle 的显式检查 API。
- SwiftUI 层仅呈现“检查更新”按钮。检查结果、发布说明、确认、进度和错误均由 Sparkle 标准更新窗口承载。
- UI testing 使用无网络的替身实现，不能访问真实 feed 或触发安装。

### 3.2 配置契约

生成的应用 Info.plist 至少包含：

- `SUFeedURL`：固定为 GitHub Pages 上的 HTTPS appcast 地址，目标路径为 `https://youranreus.github.io/TokChan/appcast.xml`。
- `SUPublicEDKey`：与发布签名私钥配对的 EdDSA 公钥。
- 禁止默认自动检查；不启用后台计划检查。显式用户检查仍通过 updater controller 提供。
- 如所选稳定版 Sparkle 支持并经兼容性验证，可启用“解压前验证”增强项；不能以此替代 Developer ID、公证或 EdDSA。

feed URL 与公钥作为可审查的非秘密构建配置进入工程。私钥只在受保护的发布环境中提供。

### 3.3 发布与托管契约

发布流程新增 Sparkle 更新资产，但不删除现有分发资产：

1. 使用与 DMG 相同的已签名、公证、装订票据的 `TokChan.app` 生成 Sparkle 支持的更新归档。首选只包含 `.app` 的 ZIP，避免把给人工安装使用的 DMG 布局内容混入更新归档。
2. 使用 Sparkle 官方工具和 EdDSA 私钥为更新归档生成签名及 appcast 条目。
3. appcast 条目使用 `CFBundleVersion` 作为 Sparkle 比较版本，并携带展示版本、HTTPS 下载地址、长度、EdDSA 签名和发布说明链接/内容。
4. 只把已发布的稳定版本纳入 feed；draft、prerelease 和非 `vX.Y.Z` 版本不得进入首版 feed。
5. 将更新 ZIP 作为 GitHub Release 资产发布；将 appcast 和发布说明部署到项目 GitHub Pages。部署顺序必须保证 feed 最后更新，避免 feed 指向尚不可下载或尚未发布的资产。
6. 继续发布并验证 DMG 与 SHA-256，供首次安装和手工恢复使用。

GitHub Pages 的 `https://youranreus.github.io/TokChan/appcast.xml` 是进入已发布客户端的兼容性契约。工作流需使用最小必要的 Pages 权限部署生成产物，不允许把 EdDSA 私钥写入 Pages artifact。

### 3.4 安全边界

每个更新必须同时满足：

- HTTPS 传输。
- Sparkle EdDSA 更新归档签名验证。
- TokChan 应用的 Developer ID 代码签名身份连续性。
- Apple 公证与票据装订要求。

SHA-256 文件继续用于人工下载验证，但不是应用内更新信任根。失败时 Sparkle 不替换现有应用；用户仍可继续运行当前版本并通过 DMG 手工恢复。

## 4. 数据与交互流

1. 用户打开设置 > 关于。
2. 按钮根据 `canCheckForUpdates` 决定是否可点击。
3. 用户点击后调用注入接口；Sparkle 打开标准检查窗口并请求 appcast。
4. 无新版本时，标准窗口明确告知已是最新版本。
5. 有新版本时，标准窗口显示版本与发布说明，等待用户确认。
6. 用户确认后，Sparkle 下载、验证、安装并按标准流程重启。
7. 任一阶段失败时，标准窗口报告错误，当前应用保持可运行；controller 恢复可检查状态后按钮重新可用。

## 5. 测试策略

- 单元测试 updater 接口适配层：动作转发、`canCheckForUpdates` 状态传播和重复触发保护。
- 视图/界面测试：关于页存在按钮；替身忙碌时按钮禁用；点击只调用一次替身且不联网。
- 发布脚本测试：更新 ZIP 内容、appcast 必要字段、稳定版本筛选、HTTPS URL、EdDSA 签名字段、发布顺序和缺失密钥时 fail closed。
- 保留现有 Xcode 单元/UI 测试与 shell 发布脚本测试。
- 端到端验收至少覆盖“旧版已安装应用 → 发现测试稳定版 → 查看说明 → 确认 → 下载 → 替换 → 重启进入新版”，并验证无更新与断网失败路径。

## 6. 兼容性、发布与回滚

- Sparkle 版本必须支持项目最低系统 macOS 13，并固定依赖版本，避免未审查升级。
- 首个带 Sparkle 的版本只能更新后续版本；历史版本不会凭空获得自更新能力。
- 首发 feed 前先用非公开测试 feed/测试 Release 完成端到端演练，再切换正式稳定 feed。
- 发布失败时不得推进 appcast。若归档已上传但 feed 未更新，它不会被客户端发现，可安全清理或重跑。
- 若线上更新资产有问题，停止更新 feed 指向该版本并发布修复版本；不得覆写已经公开发布的不可变 Release 资产。
- EdDSA 密钥轮换与 Developer ID 证书轮换必须按 Sparkle 的信任迁移规则单独设计，不能在同一版本中同时更换两条信任链。

## 7. 主要权衡

- 采用 Sparkle 标准 UI 会与关于页视觉略有差异，但显著减少自定义状态机、安全代码与可访问性负担。
- 新增 ZIP 会增加 Release 资产和 CI 工作量，但能把人工安装 DMG 与机器更新归档的职责分开。
- GitHub Pages 提供稳定 feed URL 需要额外部署步骤，但比运行自建服务简单，且保留 GitHub 基础设施约束。

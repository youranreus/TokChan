# 首次使用引导实施计划

## Preconditions

- 以 `prd.md` R1–R11 和 `design.md` 为行为真源。
- 实施前加载 macOS package specs，尤其是 state management、SwiftUI、testing、Tokscale integration 和当前 Dashboard cache/refresh 合同。
- `09-06-cache-refresh-strategy` 已修改 `DashboardViewModel` 主路径；实施必须基于当前代码增量集成，不恢复旧的单范围或有缓存不刷新行为。

## Ordered checklist

1. **先补状态机测试**
   - 为无用户名自动发现成功/失败建立确定性 fake。
   - 覆盖手填用户名 trim、保存、强制完整拉取以及重复操作防护。
   - 覆盖 all Tokens 正值、零值与 `profileNotFound` 的分流。
   - 覆盖首次提交的 `submit → fetch` 顺序、提交失败、读取失败、提交后仍为零/404。
   - 覆盖修改用户名返回路径、账号 generation 隔离，以及正常统计重试语义不回归。

2. **实现 ViewModel 引导状态与结果分类**
   - 增加 `FirstUseOnboardingState` 和只读发布状态。
   - 在初始化时从偏好和同账号完整缓存确定初始引导状态。
   - 扩展内部 profile reload 结果以保留 `profileNotFound` 类型，不从错误字符串解析。
   - 抽取唯一的“all totalTokens > 0”判定 helper。
   - 调整 `load()` 的无用户名自动发现和加载后 reconciliation，确保失败落到可手填第一步。

3. **实现显式引导动作**
   - 增加手填用户名验证/保存/强制拉取动作。
   - 增加第一步读取重试与第二步首次提交动作。
   - 增加返回修改用户名动作。
   - 复用现有 request invalidation、operation guard、CLI context 和完整批次 reload；禁止额外 submit、partial fetch 或自动循环提交。

4. **构建轻量 SwiftUI 引导视图**
   - 新建 Dashboard feature 内的 `FirstUseOnboardingView`，输入草稿保持为局部 `@State`，异步业务只调用 ViewModel 动作。
   - 第一步包含两步进度、用户名输入、继续按钮、简短无账号文案和 `https://tokscale.ai` Link。
   - 第二步包含首次提交主按钮、修改用户名次级按钮、进度及边界明确的错误/提示。
   - 添加键盘默认操作、disabled 状态、help 和稳定 accessibility identifier；不添加根背景或额外 material。

5. **接入 Dashboard 并修复恢复入口**
   - 引导未隐藏时优先渲染引导；隐藏时保留现有 Dashboard 结构、范围切换与客户端滚动。
   - 普通已配置账号加载失败继续调用 `retryStatistics()`，把含糊的“处理”文案改为明确的“重试”或为组件提供可配置动作标题。
   - 确认关闭/重开 popover 不会重置有效引导进度或显示已关闭 generation 的操作横幅。

6. **补预览与布局验证**
   - 为第一步、第二步、进行中和错误态提供无网络 Preview/fake 数据入口。
   - 扩展固定 380×680 浅色/深色渲染测试，至少覆盖两个主要引导步骤。

7. **全量检查与收尾**
   - 执行定向测试和全部 `TokChanTests`。
   - 执行 Release build；若项目标准脚本包含签名/DMG 等发布副作用，使用无发布副作用的 xcodebuild Release 构建命令。
   - 人工检查浅色/深色、官网 Link、键盘操作、长错误、用户名切换和提交后延迟可见性文案。
   - 运行 Trellis check，按结果修复后再更新 spec/提交。

## Validation commands

```bash
xcodebuild test \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -destination 'platform=macOS' \
  -only-testing:TokChanTests/DashboardViewModelTests \
  -only-testing:TokChanTests/DashboardLayoutTests

xcodebuild test \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -destination 'platform=macOS'

xcodebuild build \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -configuration Release \
  -destination 'platform=macOS'
```

## Review gates

- 没有用户名时不存在只调用 `retryStatistics()` 的无效按钮。
- `whoami`、手填验证和首次提交不会并发形成重复 fetch/submit。
- 只有完整同账号 all Tokens 正值能隐藏引导；UI 不自行重复判定。
- 404 仅在首次无资料路径进入第二步，普通已加载账号刷新失败仍保留旧批次。
- 提交成功但远端尚未出现数据时不显示成功完成，也不自动重复提交。
- 根视图仍由 AppKit NSPopover 提供背景，固定尺寸及现有 Dashboard/状态菜单合同保持不变。

## Risky files and rollback points

- `DashboardViewModel.swift`：最高风险，改动后先跑 ViewModel 定向测试；若请求合并、generation 或缓存行为回归，先回滚状态编排改动，不绕开既有 reload 管线。
- `DashboardView.swift`：接入后先跑 layout 测试；若固定布局回归，保持原 Dashboard 分支原样，只缩减引导子视图。
- `ErrorStateView.swift`：如需配置按钮标题，保持默认值兼容其他调用点并 grep 全部调用方。
- 不修改偏好/缓存 schema；回滚不需要迁移或删除用户数据。

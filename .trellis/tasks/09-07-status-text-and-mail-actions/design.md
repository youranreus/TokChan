# 状态栏用量文案与即时操作设计

## 架构与所有权

保持应用委托持有的唯一 `DashboardViewModel` 与 `NSStatusItemCoordinator`。不新增全局 store、状态项或网络服务；设置、缓存数据、状态栏标题和右键操作全部经现有共享模型协调。

新增纯展示边界（命名可在实现时按现有风格微调）：

```swift
struct StatusItemTextRenderer {
    static func render(template: String, data: DashboardData) -> String
}
```

渲染器只将模板中所有字面 `{token}`、`{cost}` 分别替换为 `DisplayFormatters.compactNumber(data.totalTokens)` 和 `DisplayFormatters.currency(data.totalCost)`。不解析其他花括号、不报错、不截断；未知内容原样保留。

## 偏好模型与兼容

在 `UserPreferences` 增加：

- `statusTextEnabled: Bool`，默认 `false`；
- `statusTextTemplate: String`，默认 `"{token} · {cost}"`；
- `statusTextPeriod: ProfilePeriod`，默认 `.day`。

`UserDefaultsPreferencesStore` 使用独立键保存。旧安装缺键时使用默认值；period 以 raw value 保存，无法构造 `ProfilePeriod` 时回退 `.day`。设置页在“常规”中增加原生 Section、Toggle、TextField 和 Picker，模板与范围控件在开关关闭时可禁用；三项仍随页面统一“保存”提交，不增加实时校验或独立保存机制。

## 状态栏数据流

`DashboardViewModel` 提供 MainActor 只读计算入口，根据已保存偏好从完整 `cachedProfiles` 查找配置范围并调用渲染器。它不保存派生标题，也不因查询触发 fetch：

1. 开关关闭、范围无缓存或渲染结果为空：返回 `nil`；
2. 有缓存：返回渲染结果；
3. 批量刷新过程中继续读取旧 `cachedProfiles`；失败不改变旧结果；
4. 成功整批发布后读取新结果。

Coordinator 观察 `preferences` 与足以代表缓存发布的既有 published 状态（实现时优先复用 `$preferences` / `$profileState`，不得建立轮询）。每次变化后在 MainActor 重算：

- 有非空标题：`statusItem.length = NSStatusItem.variableLength`，设置 `button.title`，保持模板图标位于文字左侧；
- 无标题：清空 `button.title`，恢复 `squareLength`；
- accessibility label 保持 TokChan 身份，并在有标题时包含当前可读摘要。

初始化 coordinator 时立即同步一次，保证冷启动缓存可直接显示。设置保存发布新 preferences 后立即重算，无需重启。

## 右键菜单与操作语义

扩展纯 `StatusMenuDescriptor`，加入带 enabled 状态的 push/pull action。动态菜单顺序：

1. 快照新鲜度（有则显示）；
2. 刷新诊断（有则显示）；
3. 分隔线（前述信息存在时）；
4. “立刻推送”；
5. “立刻拉取”；
6. 分隔线；
7. “设置…”；
8. “退出 TokChan”。

两个 action 以 coordinator selector 启动 MainActor `Task`：

- push-only：解析已保存 command context、解析用户名、执行一次 `cli.submit`，不调用 profile API；
- pull-only：强制执行一次完整 `reloadProfiles`，不调用 CLI submit。

扩展 `DashboardOperation` 或等价状态以覆盖 pushing/pulling。任何显式 operation 运行时两项都禁用，防止并发突变或重复请求。选择菜单项后菜单按 AppKit 默认关闭；成功不通知、不留菜单结果。push 失败写入专用轻量诊断并出现在下一次动态构建的“刷新详情”；pull 失败复用现有统计读取诊断。后续同类操作成功时清除对应旧诊断。

右键出现前仍先关闭 popover，因此由菜单发起的 operation 不应在之后重开浮窗时留下 operation banner；既有 generation/suppression 规则继续生效。

## 兼容性与边界

- 保持 macOS 13，使用 AppKit/SwiftUI/Foundation/Combine 公共 API，不新增依赖。
- 不改变完整缓存 schema；状态栏偏好属于 UserDefaults，不写入 Dashboard 快照。
- 不改变现有 `refresh()`（submit + pull）或 `runAutosubmitNow()` 语义。
- 状态文案只消费已发布缓存；`.day` 继续由 week 响应投影，不请求远端 day。
- 空或超长模板由原生状态栏处理。首版不做限制、滚动、截断配置或模板预览。

## 风险、验证与回滚

主要风险是 coordinator 更新时序、状态项 variable/square length 切换、菜单 action 与既有 operation 互斥，以及 push-only 被误接成原有组合 refresh。以纯渲染/偏好/menu/view-model 单元测试锁定语义，并在真实状态栏验证图标文字、左右键和菜单禁用状态。

回滚可分别撤销新增 UserDefaults 键读取、按钮标题订阅和两个菜单 action；不会迁移缓存或修改远端配置。遗留的 UserDefaults 新键对旧版本无害。

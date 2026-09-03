# 技术设计：更新应用与菜单栏图标

## Boundaries

- 新建 `TokChan/Assets.xcassets`，集中管理 AppIcon、菜单栏 Template Image 和“关于”页 Logo。
- `TokChanApp.swift` 只负责将 `MenuBarExtra` 从 SF Symbol 切换为 asset 名称。
- `SettingsView.swift` 只负责将“关于”页的 SF Symbol 切换为透明 Logo asset，并设置适合现有布局的缩放约束。

## Asset Design

### AppIcon

- 以 `TokChan_Logo.png` 为母版，居中生成 1024 × 1024 sRGB RGBA 图。
- 对外轮廓应用统一圆角并令四角透明，不拉伸源图。
- 从母版下采样生成 macOS AppIcon 槽位：16、32、64、128、256、512、1024 px。
- `Contents.json` 声明 16/32/128/256/512 pt 的 1x/2x 配对。

### MenuBarIcon

- 以 `TokChan_transparent.png` 的非透明边界为裁切基准，等比缩放并居中到方形透明画布。
- 将所有可见品牌像素转换为黑色，同时保留平滑 Alpha 边缘；由 asset catalog 声明 template rendering intent。
- 提供 18 × 18（1x）与 36 × 36（2x），保证标准菜单栏尺寸清晰。

### AboutLogo

- 保留透明源图的彩色内容、Alpha 与宽高比，裁去多余透明边缘后放入 image set。
- SwiftUI 使用 `resizable` + `scaledToFit`，限定显示区域，避免改变设置窗口布局。

## Integration and Compatibility

- 为 app target 的 Debug/Release 设置 `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`。
- Xcode 的 file-system synchronized group 会自动纳入 `TokChan/Assets.xcassets`，无需手写 PBX file reference。
- 使用 `MenuBarExtra(_:image:content:)` 的 macOS 13 可用 API，不提高最低系统版本。

## Risks and Rollback

- 彩色图形转换为单色后可能丢失仅靠颜色区分的内部细节；验收时以 18 pt 实际菜单栏辨识度为准，必要时调整 Alpha 阈值或留白。
- macOS 图标圆角和阴影属于视觉选择；本次只生成透明圆角，不额外伪造系统阴影。
- 回滚时删除 asset catalog、恢复两个 SF Symbol 调用并移除 AppIcon build setting 即可。

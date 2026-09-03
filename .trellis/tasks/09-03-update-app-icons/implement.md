# 实施计划：更新应用与菜单栏图标

## Checklist

1. 使用 Apple 原生 CoreGraphics/AppKit 脚本读取两张源图，规范化为 sRGB RGBA，并生成 AppIcon、MenuBarIcon、AboutLogo 文件。
2. 创建各 asset set 的 `Contents.json`，声明 macOS idiom、AppIcon 尺寸和菜单栏 template rendering intent。
3. 更新 Xcode Debug/Release app target 的 AppIcon build setting。
4. 更新 `TokChanApp.swift` 使用菜单栏图片资源。
5. 更新 `SettingsView.swift` 在“关于”页等比显示透明 Logo。
6. 检查输出图片尺寸、Alpha 通道、非透明边界和 JSON 结构。
7. 运行 `xcodebuild` 构建与测试，并检查 asset catalog 警告。

## Validation

```bash
xcodebuild -project TokChan.xcodeproj -scheme TokChan -configuration Debug build CODE_SIGNING_ALLOWED=NO
xcodebuild -project TokChan.xcodeproj -scheme TokChan test CODE_SIGNING_ALLOWED=NO
```

- 使用 `sips`/像素检查确认所有资源尺寸及 Alpha。
- 检查构建产物 `TokChan.app/Contents/Resources/Assets.car` 与应用图标声明存在。
- 人工启动应用，检查菜单栏普通/选中状态和“设置 → 关于”的实际显示。

## Review and Rollback Points

- 图片生成后、接入代码前先检查小尺寸菜单栏图标是否仍可辨识。
- 若 asset catalog 编译失败，优先回滚 `Contents.json` 或 build setting，不触碰其他设置页改动。
- 不覆盖 Downloads 中的源图；仓库内仅新增处理后的派生资源。

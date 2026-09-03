# 更新应用与菜单栏图标

## Goal

使用用户提供的 TokChan 品牌素材替换应用当前的占位 SF Symbol，使应用在 Finder/系统应用列表、菜单栏和设置“关于”页中具有一致且符合 macOS 规范的品牌识别。

## Background

- 用户提供 `/Users/reuszeng/Downloads/TokChan_Logo.png`：1254 × 1254、无 Alpha、sRGB 解码后为完整正方形画布。
- 用户提供 `/Users/reuszeng/Downloads/TokChan_transparent.png`：1295 × 1214、带 Alpha；可见内容边界约为 x=85...1256、y=37...1154。
- 当前项目没有 asset catalog；应用和“关于”页都使用 `chart.bar.xaxis` SF Symbol。
- 应用为 macOS 13+ SwiftUI 菜单栏应用，菜单栏入口由 `MenuBarExtra` 提供。

## Requirements

- R1：由不透明 Logo 生成 macOS AppIcon 资源，保持原始宽高比和品牌内容，不发生拉伸。
- R2：AppIcon 应有符合 macOS 视觉习惯的圆角外形与透明四角，并覆盖 Xcode/macOS 所需的 1x/2x 尺寸。
- R3：由透明 Logo 生成独立的单色 Template Image 菜单栏资源，在浅色、深色及选中状态下由系统正确着色，并替换现有 SF Symbol。
- R4：将透明 Logo 作为独立彩色图片资源，用于“关于”Tab，保持透明背景和宽高比。
- R5：资源必须纳入 TokChan app target，Debug 与 Release 均使用同一 AppIcon 配置。
- R6：不引入第三方图片处理或运行时依赖。

## Acceptance Criteria

- [x] AC1：构建产物的应用图标来自 TokChan Logo，在 Finder/应用信息等系统位置不是默认图标或直角满幅方块。
- [x] AC2：菜单栏显示可辨识的 TokChan 单色轮廓，能随 macOS 菜单栏状态自动切换颜色，且清晰、不拉伸、不被裁切。
- [x] AC3：“设置 → 关于”显示透明版彩色 Logo，不再显示 `chart.bar.xaxis`，背景透明且比例正确。
- [x] AC4：asset catalog 内容通过 `actool`/Xcode 构建校验，无缺失槽位或无法找到资源的警告。
- [x] AC5：项目在 macOS 13 最低部署目标下成功构建，现有测试通过。

## Out of Scope

- 重新设计、重绘或改变用户提供的品牌 Logo。
- 更换设置页各 Tab 的 SF Symbol 导航图标。
- 修改应用名称、Bundle Identifier、版本号或签名配置。
- 为文档、网站、安装器或发布商店制作额外营销素材。

## Technical Notes

- 菜单栏资源按 macOS Template Image 规范处理为透明背景和单色内容；彩色版本只用于 AppIcon 与“关于”页。
- 图片生成应可复现，并在提交前检查像素尺寸、Alpha 和资源目录声明。

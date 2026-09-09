# 自动生成中文版本发布文案

## Goal

让每个新版本在 Tag 触发的现有 Release 流程中自动生成面向用户的简体中文发布文案，准确介绍该版本相对上一版本的更新与改动，并同步用于 GitHub Release 和 Sparkle 更新说明。

## Background

- 发布由 `vX.Y.Z` Tag 触发 `.github/workflows/release.yml`，工作流创建 draft Release、上传并验证三个固定资产，随后发布 Release 和 Pages appcast。
- 当前 GitHub Release 使用 `generate_release_notes=true`，线上正文实际只有英文签名、公证与安装提示，加一条 Full Changelog 链接，没有介绍版本功能变化。
- 当前 Sparkle HTML 更新说明是固定文案，仅说明版本已签名、公证并链接 GitHub Release，同样没有版本改动内容。
- 最近版本区间同时包含用户改动提交、Trellis 归档提交和 `chore(release)` 版本提交；不能直接把提交列表当作用户文案。
- 已发布 Release 与资产保持不可变；本任务只改变未来版本的发布说明，不回写历史 Release。

## Requirements

- R1：发布文案以简体中文为主，面向普通 TokChan 用户，而不是开发者提交日志。
- R2：仓库内永久保留的中文变更片段是用户可感知改动的唯一权威来源；每项用户可感知新增、优化或修复随对应代码提交一个片段。
- R3：每个片段必须标注“新增”“优化”或“修复”；发布正文按该顺序输出分类短列表，空分类不展示，不生成营销长文。
- R4：当前版本只包含上一稳定祖先 Tag 到当前 Tag 之间首次加入的片段；历史片段不得重复、修改、重命名或删除。
- R5：生成过程必须接入现有 Tag 驱动的 GitHub Actions 发布流程，无需发布者在 GitHub 页面手工编辑 draft。
- R6：同一份规范化变更数据必须渲染为 GitHub Release Markdown 和 Sparkle HTML，两个渠道的分类与条目保持一致。
- R7：保留并中文化现有 Developer ID 签名、Apple 公证、App/DMG 公证票据、首次打开确认、DMG 拖拽安装和 SHA-256 校验说明；不得弱化现有发布安全声明。
- R8：发布基础设施、测试、文档、Trellis 归档和 `chore(release)` 等不面向用户的改动不创建片段，也不会进入正文。
- R9：没有有效片段、片段非法、历史片段被篡改、生成失败或输出缺少强制安全说明时，必须在 Release 发布前失败，不得编造“例行优化”等占位内容。
- R10：同一 Tag 的生成结果必须可重现；draft 可按 Tag 源码中的期望正文自动校正并复验，已发布 Release 只读且不得改写。
- R11：生成器不得依赖网络、GitHub API、Apple/Sparkle 凭据或第三方运行时依赖，并应在凭据注入和构建之前执行。
- R12：生成和发布行为必须可通过离线自动化测试验证。
- R13：fragment 完整性通过 Trellis 规划、实现和检查流程约束，不新增常规 PR/push CI 门禁；人工绕过 Trellis 的提交不在本任务中机械阻止。

## Acceptance Criteria

- [ ] AC1：推送新的稳定 SemVer Tag 后，工作流自动创建包含中文“本次更新”的 draft Release，无需网页端人工补写。
- [ ] AC2：正文按“新增 → 优化 → 修复”展示当前版本首次加入的片段，只显示非空分类。
- [ ] AC3：上一稳定 Tag 已存在的片段不会重复出现；历史片段的修改、删除或重命名会阻止发布。
- [ ] AC4：GitHub Release 与 Sparkle HTML 从同一规范化数据生成，解析后得到完全相同的分类和条目顺序。
- [ ] AC5：两个渠道均包含完整中文签名、公证、票据、首次打开、安装与校验提示，现有安全边界不被削弱。
- [ ] AC6：无有效片段、非法片段、异常 Tag 拓扑或非法输出时，工作流在 GitHub Release mutation、Apple/Sparkle 凭据使用和 Pages 部署前失败。
- [ ] AC7：同一 Tag 重跑得到逐字节一致的输出；draft 正文可被确定性校正，published Release 在恢复流程中仅校验且不被 PATCH。
- [ ] AC8：首个稳定 Tag 可使用当前树中的全部合法片段；仓库已有稳定 Tag 但当前 Tag 没有稳定祖先时失败。
- [ ] AC9：离线测试覆盖正常三分类、空分类、区间选择、首个 Tag、无片段、非法 JSON/字段/中文内容、历史篡改、HTML 转义、重复运行和 Release 状态机。
- [ ] AC10：维护者文档说明何时需要片段、文件格式、分类、用户视角写法及发布失败后的修正方式。
- [ ] AC11：Trellis release-workflow spec 明确要求每个任务判断用户可感知影响，实施与检查阶段验证应有 fragment 的改动已携带对应中文片段；不会新增常规 PR/push CI。

## Out of Scope

- 修改历史 GitHub Releases 或历史 Sparkle 更新说明。
- 改变版本号、Tag、签名、公证、资产命名或 Sparkle 信任链。
- 自动发布预发布版本或非 SemVer Tag。
- 新增常规 pull request 或 push CI 门禁来强制 fragment。
- 生成英文、多语言、AI 文案或营销长文。
- 从 commit subject、代码 diff 或 Trellis 任务内容推断用户价值。

## Product Decisions

- 使用仓库内中文变更片段，而不是发布时调用 AI 或按英文提交记录套模板；发布阶段自动聚合和渲染。
- 正文采用“新增 / 优化 / 修复”的分类短列表，同一版本只展示有内容的分类。
- 没有用户可感知片段的版本 fail closed，不提供隐式绕过开关。
- fragment 完整性采用 Trellis spec 与实现/检查流程约束，不新增常规 CI 硬门禁。
- 本任务虽然改动发布基础设施，但会直接改善用户看到的 GitHub Release 与 Sparkle 更新说明，因此作为用户可感知优化新增一个 fragment。

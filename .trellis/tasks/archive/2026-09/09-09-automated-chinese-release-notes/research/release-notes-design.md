# 中文发布说明生成与发布设计调研

> 调研日期：2026-09-09
> 范围：仓库现状、草稿重试与已发布恢复语义、Sparkle 发布说明、离线测试接缝，以及仓库内变更片段的推荐契约。本文只提供设计建议。

## 1. 结论

建议新增一个**无网络、无凭据、只依赖 Python 标准库和 Git 的仓库脚本**，以当前稳定 Tag 和其上一祖先稳定 Tag 为输入，从永久保留的 `release-notes/fragments/*.json` 中选择本版本首次出现的片段，构造同一个内存模型，再一次性输出：

1. GitHub Release Markdown 正文；
2. Sparkle 使用的完整 HTML 发布说明；
3. 可选的规范化 JSON 清单，供测试和跨渠道一致性校验使用。

核心原则：

- 片段是唯一的用户改动事实源，不再从 commit subject 猜测用户价值。
- 分类固定为 `新增`、`优化`、`修复`，分类按此顺序展示，空分类不展示。
- 片段永久保留且发布后不可修改或删除；某版本只选择“上一稳定 Tag 中不存在、当前 Tag 中存在”的片段。
- 没有上一稳定 Tag 时，只在仓库确实没有任何其他稳定 Tag 的情况下，把当前 Tag 下全部片段视为首发内容。
- 没有有效片段时失败，不生成“例行更新”等虚构条目。
- 发布说明在任何 Apple/Sparkle 私钥注入之前生成和验证；后续 appcast 步骤只消费已生成 HTML。
- draft 可以被确定性地校正后复用；published Release 的正文和资产只读校验，绝不 PATCH、重传或重发。
- 移除 `generate_release_notes=true`，避免 GitHub 在规范正文后追加不可控、面向开发者的提交列表和 Full Changelog。

## 2. 当前仓库行为

### 2.1 当前发布说明来源

`.github/workflows/release.yml` 的 `Create or resume draft Release` 步骤只在 Release 不存在时创建正文：

- 传入一段英文 `distribution_notes`；
- 同时传 `generate_release_notes=true`；
- GitHub 将传入的 `body` 前置到自动生成内容之前。

GitHub 官方 REST 文档明确说明：创建 Release 时若同时指定 `body` 和 `generate_release_notes=true`，`body` 会被前置到自动生成说明。仓库线上 `v1.0.8` 的实际正文也印证了结果：英文签名/公证与安装提示，随后只有 `Full Changelog: ...v1.0.7...v1.0.8`，没有用户功能摘要。

当前已有 draft 时，工作流不会重写正文，只读取 `.body` 并搜索四段固定英文安全文字；包含旧的未签名声明时也会拒绝。正文没有和源码中的某个完整期望值逐字比较。

来源：

- `.github/workflows/release.yml`，`Create or resume draft Release` 步骤。
- GitHub REST API，Create a release：<https://docs.github.com/en/rest/releases/releases#create-a-release>。
- 线上 Release：`gh release view v1.0.8 --json tagName,isDraft,body,url`，调研时返回已发布正文及 Full Changelog 链接。

### 2.2 当前 Sparkle HTML 与 feed 发布

`Generate signed Sparkle appcast` 步骤当前在持有 `SPARKLE_PRIVATE_KEY_BASE64` 的同一个 shell block 中：

1. 解码并验证 Sparkle 私钥/公钥配对；
2. 下载已部署的旧 appcast 和其引用的历史 HTML；
3. 用 heredoc 生成当前 HTML，内容只有版本标题、Developer ID/Apple 公证一句话和 GitHub Release 链接；
4. 调用 Sparkle `generate_appcast`；
5. 验证当前 enclosure、版本、长度、EdDSA 签名、releaseNotesLink，并证明历史 feed item 未变化；
6. 删除凭据与 ZIP 后，把 appcast 和所有 HTML 复制到 `pages/`。

Sparkle 官方文档支持以 `sparkle:releaseNotesLink` 指向外部 HTML；也支持在 appcast 中嵌入 HTML/plain text。当前仓库已经选择外部 HTML，并具备历史 HTML 保留逻辑，因此本任务应继续使用该形态，只替换当前 HTML 的生成来源。Sparkle 文档还说明，更新归档签名由 `generate_appcast` 推荐生成；发布说明文件只有在应用启用 `SURequireSignedFeed` 时另需签名。当前任务不应改变既有 EdDSA enclosure 信任链。

来源：

- `.github/workflows/release.yml`，`Generate signed Sparkle appcast` 步骤。
- Sparkle Publishing 文档，External/Embedded/Full release notes 与 update signing：<https://sparkle-project.org/documentation/publishing/>。
- `.trellis/spec/macos/release-workflow.md` 第 3、6、8 节。

### 2.3 发布顺序和不可变恢复

现有状态机是：

1. 校验 Tag、源码版本及其位于 `origin/master` 历史中；
2. `Inspect immutable Release recovery state` 查询同 Tag Release；
3. absent/draft 时正常构建，published 且 `github.run_attempt >= 2` 时下载三个已发布资产进入 feed-only recovery；
4. 私下生成并验证候选 appcast；
5. absent 时创建 draft，draft 时复用；
6. 非 recovery 路径用 `gh release upload --clobber` 替换**草稿**资产，逐字节下载复验后发布；
7. recovery 路径不上传、不 PATCH Release，只校验远端精确三资产及字节；
8. Release ZIP 可公开下载后才上传 Pages artifact，最后部署 appcast。

这形成两个重要边界：

- **draft 是可恢复事务区**，正文和资产都可以在确认仍为 draft 后校正；
- **published 是不可变输入**，仅允许同一次失败 workflow 的后续 attempt 做 feed-only recovery，且必须复验资产，不能改正文或附件。

发布说明改造必须保持 `candidate generated -> draft assets/body verified -> Release published -> Pages deployed last`，不能为了写说明把 Pages 提前，也不能在 recovery 中 PATCH 已发布正文。

来源：

- `.github/workflows/release.yml` 的 `Inspect immutable Release recovery state`、`Create or resume draft Release`、`Verify published update archive`、`Deploy appcast last`。
- `.trellis/spec/macos/release-workflow.md`：published Release/asset immutable、Pages 为发现提交点、feed-only recovery。
- `docs/macos-release.md` 第 4、5 节。

### 2.4 现有提交历史为何不适合作为正文来源

`v1.0.7..v1.0.8` 只有三条顶层提交：

- `fix(autosubmit): recover from invalid launchd bootout`，是用户可感知修复；
- `chore(task): archive ...`，是 Trellis 归档噪音；
- `chore(release): v1.0.8`，是版本噪音。

该区间的文件 diff 又混合产品代码、测试、版本文件、spec 和整套归档任务。更早区间还有 merge、journal、docs、release 基础设施修复。仅按 Conventional Commit 前缀或 subject 排除会持续误判，也不能稳定产出简体中文用户文案。片段契约让噪音提交天然没有输入，不需要持续扩充 commit 过滤正则。

来源：

- `git log --format='%h %s' v1.0.7..v1.0.8`。
- `git diff --name-status v1.0.7..v1.0.8`。
- 仓库稳定 Tag 列表 `v0.1.1` 至 `v1.0.8` 的逐区间日志。

## 3. 推荐的仓库片段契约

### 3.1 路径与格式

推荐路径：

```text
release-notes/fragments/20260909-autosubmit-launchd-recovery.json
```

每个文件只描述一项用户可感知改动：

```json
{
  "category": "修复",
  "summary": "修复自动提交服务状态异常后无法恢复的问题"
}
```

选择 JSON 而不是自由 Markdown或 YAML 的原因：

- Python 标准库可严格解析，无新增 CI 依赖；
- 字段和未知键可 fail closed；
- 同一结构可安全渲染 Markdown 与 HTML，避免从一个展示格式反向解析另一个；
- review 时仍足够可读。

### 3.2 严格验证规则

建议生成器拒绝以下输入：

- 文件名不匹配 `^[0-9]{8}-[a-z0-9][a-z0-9-]*\.json$`，或目录内存在非 JSON 普通文件/符号链接；
- 非 UTF-8、重复 JSON key、根节点不是 object；
- 字段不是且不恰好是 `category`、`summary`；
- `category` 不属于 `新增`、`优化`、`修复`；
- `summary` 不是单行字符串、有首尾空白、控制字符、HTML 标签，或不处于 NFC；
- `summary` 不含至少一个汉字，或长度超出建议的 8–80 个 Unicode 字符；
- 同一发布区间出现重复 summary；
- 总条目超过建议上限 12。超过时应由维护者人工合并片段，而不是由 CI 截断。

渲染时仍需分别执行 Markdown 文本转义和 HTML escaping，不能因为输入规则较严就直接拼接 HTML。不得允许片段携带原始 Markdown/HTML、脚本、图片或任意模板字段。

`summary` 应写用户结果，例如“修复自动提交服务状态异常后无法恢复的问题”，而不是实现过程，例如“修改 `launchctl bootout` fallback”。发布基础设施、测试、重构、Trellis 归档和版本递增不创建片段。

### 3.3 生命周期与 Tag 区间

片段应采用**追加、永久保留、发布后不可改**的生命周期：

1. 用户可感知功能/修复与对应代码一起提交片段；多个代码提交可以共同完善一个尚未发布的新增片段。
2. Tag 生成时找出当前 Tag 的上一稳定祖先 Tag。
3. 选择上一 Tag 不存在、当前 Tag 存在的片段。
4. 发布后片段留在原路径，成为可审计历史；下一版本不会再次选择它。
5. 如果上一 Tag 已存在某片段，而当前 Tag 修改、重命名或删除它，生成失败。历史文案修正必须通过新版本的新片段表达，不回写旧发布事实。

不建议“发布后删除/移动片段”：Tag workflow 无权向默认分支回写清理提交；添加后又在 Tag 前删除的片段会从端点 diff 消失；draft retry 也更难证明输入不变。永久文件的存储成本很小，却能直接支持可重现和审计。

为捕获“区间内添加后删除”以及 rename 等端点 diff 看不到的情况，生成器不应只运行 `git diff --diff-filter=A`。更稳妥的算法是：

1. 用 `git log --format= --name-only <previous>..<current> -- release-notes/fragments` 收集区间内触碰过的全部路径；
2. 对每个路径分别查询 previous/current blob 是否存在及 blob ID；
3. previous 缺失、current 存在：本版本新片段，允许；
4. previous 存在、current blob 相同：不是新片段，不输出；
5. previous 存在而 current 不同/缺失，或两端都缺失但区间曾触碰：拒绝历史修改、删除或瞬时片段；
6. 再枚举 current 树下目录，拒绝异常文件和未被算法正确分类的状态。

因为输入来自 Git object（例如 `git show "$CURRENT:$path"`），而不是可变工作树，所以 Tag 重跑得到相同字节。

### 3.4 上一稳定 Tag 的确定

稳定 Tag 必须完整匹配 `^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$`。建议：

- current 必须匹配并解析为整数三元组；
- 候选必须是 current commit 的祖先、不能等于 current；
- 取 SemVer 三元组最大的候选，而不是按创建日期、字典序或 `git describe` 距离取值；
- 若祖先中存在版本号大于等于 current 的其他稳定 Tag，拒绝倒序/重复发布拓扑；
- 若仓库存在其他稳定 Tag、但 current 没有稳定祖先，拒绝把分叉历史误判成首发。

这比依赖 GitHub 自动 release-note range 更明确。GitHub 的 Generate release notes API虽然允许 `previous_tag_name`，但本方案无需网络，且片段区间可以在离线测试中完整复现。

来源：GitHub REST API，Generate release notes content：<https://docs.github.com/en/rest/releases/releases#generate-release-notes-content-for-a-release>。

### 3.5 首个 Tag 与无片段

- **真正首个稳定 Tag**：仓库没有其他稳定 Tag时，选择 current 树中全部合法片段。
- **已有稳定 Tag 但 current 无稳定祖先**：失败，提示异常 Tag 拓扑。
- **选中片段为零**：失败，不创建/发布 Release，不部署 appcast。
- **只有 release/Trellis/docs/internal 变更**：因为没有片段，按上一条失败；不得自动写“性能优化”“其他改进”等占位内容。

PRD AC5 已明确要求无有效改动时在公开 Release 和新 appcast 前失败，因此不建议设计 `no-user-changes` 哨兵来绕过门禁。如果未来业务确实需要纯基础设施版本，应先修改产品要求，再增加显式、受审查的例外，而不是在本任务中暗留逃生口。

## 4. 推荐展示结构

### 4.1 GitHub Markdown

建议正文短而完整，关闭 GitHub 自动生成说明：

```markdown
## 本次更新

### 新增
- 新增……

### 优化
- 优化……

### 修复
- 修复……

## 下载与安全说明

> [!NOTE]
> 本版本使用 Developer ID 签名并通过 Apple 公证，TokChan.app 与 DMG 均已装订公证票据。macOS 仍可能要求确认打开从互联网下载的应用。

下载 DMG 后，将 TokChan.app 拖到镜像中的“应用程序”文件夹完成安装。使用前请按随附的 `.sha256` 文件校验 DMG 的 SHA-256，校验失败时不要安装或运行。
```

只展示有条目的分类。建议 1–12 条，每条一句，不生成营销长文。GitHub Release 创建时省略或显式设 `generate_release_notes=false`；如需 compare 链接，应由确定性模板显式产生，而不是重新开启自动生成。

### 4.2 Sparkle HTML

HTML 使用同一规范化条目模型和同样的分类/条目顺序，并包含同一组中文安全声明、DMG 安装与 SHA-256 指引。可在末尾保留“在 GitHub 查看此版本”链接。示意：

```html
<!doctype html>
<html lang="zh-CN">
  <head><meta charset="utf-8"><title>TokChan 1.0.9 更新说明</title></head>
  <body>
    <h1>TokChan 1.0.9</h1>
    <h2>本次更新</h2>
    <h3>修复</h3>
    <ul><li>修复……</li></ul>
    <h2>下载与安全说明</h2>
    <p>本版本使用 Developer ID 签名并通过 Apple 公证……</p>
  </body>
</html>
```

“一致”应定义为两个渠道从同一 canonical model 渲染，且自动化测试解析 Markdown/HTML 后得到完全相同的 `(category, summary)` 序列；不要通过字符串复制后再人工维护两套条目。

安全说明也应来自生成器内的同一常量集合，分别渲染为 Markdown/HTML。验证器检查完整规范正文或结构化安全声明 ID，而不是只 grep 一个宽泛关键词。

## 5. 推荐工作流接入点

建议顺序：

1. checkout（`fetch-depth: 0` 保持）；
2. 校验 current Tag、工程版本、默认分支可达性；
3. **生成并验证发布说明**，输出到 `$RUNNER_TEMP/release-notes/github.md`、`sparkle.html`、`manifest.json`；
4. 查询 immutable recovery state；
5. 正常路径注入 Apple 凭据并构建；recovery 路径下载不可变资产；
6. appcast 步骤读取预生成 `sparkle.html`，不再在私钥 shell block 中拼文案；
7. absent/draft Release 处理；
8. 发布 Release、验证公开 ZIP；
9. 上传 Pages artifact 并最后部署。

生成放在凭据步骤之前有三个好处：格式、区间、空内容错误能最早失败；脚本不接触 Apple/Sparkle secrets；离线测试无需模拟签名环境。输出不要放在 `dist/` 顶层，以免破坏“精确三个资产”契约，也不要提交到 Pages 目录直到私钥已删除且 appcast 验证完成。

### 5.1 absent / draft / published 行为

**Release absent**

- 先生成完整 expected Markdown；
- POST draft 时 `body` 直接读取该文件；
- 不启用 `generate_release_notes`；
- 创建后重新 GET，并逐字节比较 `.body == expected`，再上传资产。

**Release draft**

- 再确认 `.draft == true` 后，可 PATCH body 为 expected；
- PATCH 后重新 GET，要求仍为 draft 且正文逐字节一致；
- 再按现有 `--clobber` 逻辑替换和复验草稿资产。

这样可恢复旧的部分草稿，也不会依赖人工网页编辑。若更保守，也可在正文不一致时失败而不 PATCH；但这会使由旧工作流创建的 draft 无法自动恢复。既有契约已允许 draft 资产替换，因此只在 draft 状态下确定性校正文字符合当前事务模型。

**Release published / feed-only recovery**

- 禁止 PATCH body、禁止上传资产、禁止改变 Release 状态；
- GET 正文并与 tagged source 重新生成的 expected Markdown 逐字节比较；不一致则失败并要求人工调查，不能“修复”已发布正文；
- 继续使用已下载且逐字节验证的不可变 ZIP 生成 appcast，并使用同一 tagged source 的 HTML；
- Pages 仍最后部署。

所有 PATCH/upload 前后都保留现有 draft 状态复查，防止并发或人工发布造成越界。

### 5.2 凭据边界

发布说明生成器应满足：

- 不调用 GitHub API，不读取 `GH_TOKEN`，不读取 Apple/Sparkle 环境变量；
- 不运行 Xcode、Sparkle、curl；
- 只读取指定 Git refs 和片段路径，写入显式输出目录；
- 错误中只打印路径和校验原因，不打印完整环境；
- appcast 私钥步骤只得到 HTML 文件路径，不得到修改 fragment 或 GitHub正文的职责；
- 私钥删除、ZIP 移除和 Pages allowlist 校验继续保持在现有位置。

当前 job 级 `GH_TOKEN` 仍会由 workflow 环境继承；若要使边界可机械证明，可在生成步骤显式覆盖为空，或者将 token 从 job env 下沉到仅使用 `gh` 的步骤。无论采用哪种方式，都不应扩大现有 `contents/pages/id-token` 权限。

## 6. 离线测试接缝

### 6.1 当前可复用接缝

`tests/test_release_scripts.sh` 已具备以下模式：

- 解析 workflow 中每个 `run: |` block 并执行 `bash -n`；
- 按步骤名称抽取 `Generate signed Sparkle appcast` 和 `Create or resume draft Release` shell；
- 用本地 `curl`、`xcodebuild`、`generate_appcast`、`sign_update`、`gh` mock 执行步骤；
- 覆盖首个 feed 404、历史 feed/HTML 保留、旧 item 被修改、网络失败、Sparkle keypair 不匹配；
- 覆盖 absent 创建、draft 复用、缺安全文案、published 首次 attempt 拒绝、后续 attempt feed-only recovery、资产集合不精确；
- 结构性断言候选 appcast 先于 draft Release、Pages 最后部署，权限/凭据/action pin 精确。

这些测试接缝可以保留，但不应继续把越来越大的业务逻辑只写在 YAML heredoc 中。

来源：`tests/test_release_scripts.sh` 中 appcast-step、workflow-step 提取与 mock 区段；`.trellis/spec/macos/release-workflow.md` 第 6 节。

### 6.2 推荐新增测试层

**A. 生成器单元/集成测试（主要行为层）**

在临时 Git 仓库创建 commits 和 annotated tags，直接调用脚本，覆盖：

- 正常 previous..current：三分类、固定排序、空分类省略；
- commit 区间混入 `chore(release)`、Trellis archive、merge/docs，但无片段时不产生条目；
- 只选择本区间新增片段，不重复上一 Tag 片段；
- 首个稳定 Tag 选择全部片段；
- 仓库有稳定 Tag但 current 无稳定祖先时失败；
- 无片段/只有噪音时失败；
- 非 SemVer current、倒序 Tag、重复/异常 Tag 拓扑失败；
- 非法 JSON、重复 key、未知字段、非法分类、非中文/多行/过长 summary、重复 summary、条目超限失败；
- 已发布片段修改、删除、rename，以及区间内添加后删除失败；
- HTML 特殊字符被 escaping，不能注入标签；
- 同一 refs 重跑输出逐字节相同；
- Markdown 与 HTML 解析出的 canonical 条目序列完全一致；
- 两个渠道都包含全部强制中文安全声明。

**B. workflow 结构测试**

断言：

- 生成步骤位于任何 Secret 注入/构建和 appcast 之前；
- appcast 从生成器输出复制 HTML，不含内联用户条目模板；
- Release POST body 来自生成文件且没有 `generate_release_notes=true`；
- 发布说明验证先于资产上传和 `draft=false`；
- Pages 仍在 Release 发布及公开 ZIP 校验后部署；
- permissions、action pins、三资产和现有凭据 allowlist 不变。

**C. `gh` mock 状态机测试**

扩展现有 mock 记录 POST/PATCH body：

- absent 创建的 body 与 expected 完全相同；
- draft 正文漂移时仅 draft 可 PATCH，PATCH 后复验；
- draft 在 PATCH/upload 间变 published 时拒绝；
- published attempt 1 仍拒绝；
- published attempt 2 正文匹配时只读 recovery 成功；
- published 正文不匹配时失败且 mock 证明没有 PATCH/upload；
- 缺任一安全声明、条目为空、占位内容均在发布前失败。

**D. appcast mock 测试**

在现有 feed fixture 上增加：

- 当前 HTML 与 generator 输出逐字节相同；
- 历史 HTML 仍原样保留；
- `manifest.json` 不进入 Pages artifact；
- private key、ZIP、临时路径仍不进入 Pages；
- 发布说明生成失败时 appcast 工具、GitHub mutation 和 Pages upload均未调用。

## 7. 需要在技术设计中明确的决定

建议后续设计直接固定以下选择，避免实现阶段重新分叉：

1. 目录为 `release-notes/fragments/`，格式为一项一文件的严格 JSON。
2. 片段永久追加；已出现于稳定 Tag 的片段禁止修改、删除、rename。
3. previous 是 current 的最大 SemVer 稳定祖先 Tag。
4. 真正首发读取全部片段；无有效片段一律 fail closed。
5. 分类顺序 `新增 -> 优化 -> 修复`，每版最多 12 条，每条 8–80 字；空分类不显示。
6. GitHub Markdown 与 Sparkle HTML 从同一 canonical model 渲染，核心条目序列必须相同。
7. 安全声明使用一组中文常量同时渲染到两个渠道，至少完整覆盖 Developer ID、Apple 公证、App/DMG stapled tickets、首次打开确认、DMG 拖拽安装、SHA-256 校验与校验失败不安装。
8. 禁用 GitHub自动 release notes。
9. draft 可确定性 PATCH 并复验；published 只读逐字节校验，recovery 永不改 Release。
10. 发布说明生成独立于 Apple/Sparkle/GitHub 凭据，位于所有凭据步骤之前；Pages 仍最后部署。

## 8. 风险与取舍

- **永久片段会增长**：增长速度等于用户可感知条目数，远小于源码和归档任务；换来可审计、可重现和无清理提交。
- **严格无片段失败会阻止纯基础设施版本**：这是 PRD AC5 的直接要求，也能防止发布空洞版本；若需求改变应显式改契约。
- **draft 自动 PATCH 会覆盖人工草稿编辑**：当前目标本就要求无需网页编辑，且 draft 是可恢复事务区。published 仍完全不可写。
- **全文逐字节校验对模板升级敏感**：workflow rerun 使用 Tag 所指源码中的脚本，因此同 Tag 重跑仍稳定；新模板只影响未来 Tag。不要从默认分支动态下载生成器。
- **只检查端点 diff 会漏掉瞬时片段**：应按 3.3 的 touched-path + 两端 blob 算法，而不是单独依赖 `git diff --diff-filter=A`。
- **HTML 与 Markdown escaping 不同**：共享数据模型，不共享未转义字符串模板；分别渲染并用结构测试比较核心条目。

## 9. 主要来源

### 仓库内

- `.github/workflows/release.yml`
- `tests/test_release_scripts.sh`
- `.trellis/spec/macos/release-workflow.md`
- `docs/macos-release.md`
- `.trellis/tasks/archive/2026-09/09-08-github-app-self-update/design.md`
- `.trellis/tasks/archive/2026-09/09-08-github-app-self-update/implement.md`
- Git 历史与稳定 Tag 区间，重点为 `v1.0.7..v1.0.8`

### 官方外部资料

- GitHub REST API，Create a release：<https://docs.github.com/en/rest/releases/releases#create-a-release>
- GitHub REST API，Generate release notes content：<https://docs.github.com/en/rest/releases/releases#generate-release-notes-content-for-a-release>
- Sparkle Publishing：<https://sparkle-project.org/documentation/publishing/>

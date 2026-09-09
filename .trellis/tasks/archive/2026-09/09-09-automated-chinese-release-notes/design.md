# Design

## 1. Boundary

Add a deterministic release-note generator at the source/Tag boundary. Repository-owned Chinese fragments describe user-visible changes; the generator resolves the previous stable ancestor Tag, validates fragment history, builds one canonical model, then renders GitHub Markdown and Sparkle HTML. The workflow consumes those files but keeps the existing signing, notarization, immutable-asset, draft, and Pages-last boundaries.

The generator is not a changelog inferred from commits and does not call an LLM or GitHub. It uses Python standard library plus Git so output is reviewable, reproducible, and available before any credential-bearing step.

## 2. Fragment contract

Path:

```text
release-notes/fragments/YYYYMMDD-lowercase-slug.json
```

One file describes one user-visible outcome:

```json
{
  "category": "修复",
  "summary": "修复自动提交服务状态异常后无法恢复的问题"
}
```

Contract:

- exact keys: `category`, `summary`;
- categories: `新增`, `优化`, `修复`, rendered in that order;
- UTF-8 JSON object with duplicate-key rejection and no unknown keys;
- summary is NFC-normalized, single-line, trimmed, contains at least one Han character, contains no control characters or HTML tags, and is 8–80 Unicode code points;
- duplicate summaries and more than 12 selected entries fail;
- directory entries must match the filename pattern and may not be symlinks;
- fragments are append-only and permanent after appearing in a stable Tag.

Internal, test, documentation, release-infrastructure, Trellis archive, and version-only changes do not receive fragments.

## 3. Generator interface and outputs

Add:

```text
python3 scripts/generate-release-notes.py \
  --tag vX.Y.Z \
  --repository owner/repo \
  --output-dir <owned-empty-directory>
```

Outputs:

```text
github.md
sparkle.html
manifest.json
```

`manifest.json` is the canonical version/category/summary model used by tests and workflow validation; it is never uploaded as a Release asset or Pages file. Output creation is staged and all three files appear only after complete validation.

Both presentation formats include the same category/summary sequence and the same canonical Chinese safety facts. Markdown contains `## 本次更新` and `## 下载与安全说明`. HTML uses `lang="zh-CN"`, UTF-8 metadata, semantic headings/lists, escaped text, and a same-Tag GitHub Release link.

## 4. Tag and history algorithm

- Require current Tag to match stable SemVer `vX.Y.Z` and resolve to a commit.
- Enumerate other stable Tags that are ancestors of current; select the numerically greatest SemVer as previous.
- Reject another stable ancestor whose SemVer is greater than or equal to current.
- If no stable ancestor exists but any other stable Tag exists in the repository, reject divergent history. A repository with no other stable Tag is the true-first-release case.
- Collect every fragment path touched in `previous..current`; compare blobs at both endpoints.
  - absent before and present now: selected new fragment;
  - present before and byte-identical now: historical, not selected;
  - present before and changed/deleted, or absent at both endpoints after being touched: reject mutation/deletion/transient fragment;
- For a true first release, select all legal fragments in the current tree.
- Read fragment bytes from Git objects, not the mutable working tree.
- Reject zero selected fragments.

Sort selected entries by category order and then stable fragment path. This gives byte-identical output for repeated runs against the same Tag.


## 5. Authoring enforcement through Trellis

Do not add a general pull-request or push CI workflow. Instead, extend `.trellis/spec/macos/release-workflow.md` so every Trellis-planned macOS task must classify whether it changes user-visible behavior:

- planning records the release-note impact in task requirements or implementation notes;
- implementation adds one fragment per independently explainable user outcome and adds none for internal-only work;
- quality check compares the complete user-visible diff against newly added fragments, checking coverage, category, wording, and duplicates;
- task completion must not proceed with an unexplained user-visible change.

The Tag workflow remains a final format/history/empty-selection gate, not a semantic proof that every feature was described. Direct manual commits that bypass Trellis are an accepted limitation of this choice.

## 6. Workflow data flow

1. Checkout full history and validate Tag/source version.
2. Generate release notes into `$RUNNER_TEMP/release-notes` with credential variables explicitly absent from the step.
3. Validate all three outputs before inspecting or mutating remote Release state.
4. Normal build or immutable published-asset recovery proceeds unchanged.
5. Appcast generation copies the pre-generated `sparkle.html`; it no longer constructs current-version HTML inside the Sparkle private-key block.
6. Release publication reads `github.md` as the exact expected body and disables GitHub `generate_release_notes`.
7. For an absent Release, create a draft with exact body then GET/compare it.
8. For a draft, re-check draft state, PATCH exact body if needed, GET/compare, then continue existing draft asset replacement and verification.
9. For a published recovery, never PATCH body or upload assets; GET and compare exact body before feed-only recovery.
10. Publish Release, verify public ZIP, assemble allowlisted Pages files, and deploy appcast last as today.

## 7. Compatibility and migration

Historical Releases and historical HTML are untouched. The first future Tag containing this feature compares against the preceding Tag, whose tree may not contain `release-notes/fragments/`; newly added fragments in the new Tag are selected normally. Existing Tags rerun their own tagged workflow source and therefore do not execute the new generator.

GitHub's automatic generated notes are removed for future Releases to avoid an uncontrolled English Full Changelog section. A deterministic compare link may be rendered by the template if desired, but it is not a substitute for fragments.

## 8. Failure and rollback

All malformed fragments, abnormal Tag topology, historical fragment mutation, empty selection, rendering mismatch, unsafe output paths, or body mismatch fail before public mutation. Draft-only body correction remains reversible and transaction-scoped; published Releases remain immutable.

Rollback is a coherent revert of generator, workflow integration, docs, and tests before creating a new Tag. Never repair a published Tag by moving it or replacing its body/assets. If a bad note reaches publication, issue a new patch under the existing release policy.

## 9. Trade-offs

Permanent fragments add small repository growth but make history auditable and avoid CI cleanup commits. Strict empty-selection failure prevents infrastructure-only releases; this is intentional to avoid empty or fabricated user notes. Exact body comparison makes template changes apply only to future Tags because reruns execute tagged source.

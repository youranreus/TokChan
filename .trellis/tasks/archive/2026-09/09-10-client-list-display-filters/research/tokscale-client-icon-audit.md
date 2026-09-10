# Tokscale client icon audit

Audited against local Tokscale checkout commit `4b343e43bf0f1aa78f5032cb082f1c2c4cc76f65` (2026-09-10), using `packages/frontend/src/lib/types.ts` (`SUPPORTED_CLIENT_TYPES`) as the authoritative server-facing client-ID registry and `packages/frontend/src/lib/constants.ts` (`SOURCE_LOGOS`) as the icon-source registry.

## Result

Tokscale currently declares 55 supported client IDs. Before alignment, TokChan's `ClientIcon.knownClients` held 32 asset-base names and resolved only the older catalog plus a handful of aliases. The following current IDs lacked a dedicated or explicit compatible mapping:

`mcode`, `kiro`, `warp`, `cline`, `gjc`, `9router`, `grok`, `commandcode`, `micode`, `antigravity-cli`, `junie`, `zcode`, `opencodereview`, `workbuddy`, `devin-cli`, `devin-desktop`, `augment`, `kimchi`, `reasonix`, `prime-agent`, `dsh`, `omp`, `lmstudio`, `unsloth`.

## Compatibility mapping

The following IDs represent the same branded product or an upstream-declared shared mark and should intentionally reuse one asset:

- `codex` → `client-openai`
- `kilo` → `client-kilocode`
- `antigravity-cli` → `client-antigravity`
- `devin-cli`, `devin-desktop` → `client-devin`
- `reasonix` → `client-synthetic` (matches Tokscale `SOURCE_LOGOS`)
- `9router` → `client-gjc` (Tokscale documents this as a temporary shared gjc mark)

Legacy TokChan inputs `openai`, `claude-code`, `github-copilot`, and `roo` remain aliases for compatibility but are not members of Tokscale's current authoritative 55-ID set.

## Distinct-product safeguards

`codebuddy` and `codebuff` are unrelated products. They must resolve to `client-codebuddy` and `client-codebuff` respectively. `workbuddy` is also a separate product and receives `client-workbuddy`.

## New unique assets

The conservative full-alignment set adds unique assets for MiniMax Code (`mcode`), Kiro, Warp, Cline, Gajae-Code, Grok Build, Command Code, MiMo Code, Junie, ZCode, OpenCodeReview, WorkBuddy, Augment Code, Kimchi, Prime Agent, DeepSeek Harness, Oh My Pi, LM Studio, and Unsloth. Exact source URLs and SHA-256 checksums are recorded in `TokChan/Resources/ClientOriginals/provenance.json` after download.

## Licensing caveat

Tokscale's repository license covers files copied from its repository, but it does not automatically license third-party logos fetched from external product/GitHub URLs. External files are retained with URL/checksum provenance and an explicit note to consult the owner's terms. Logos are used only for product identification; no ownership or endorsement is implied.

# Tokscale period and asset contract

Verified 2026-09-04 against official main source and live public responses.

## Sources

- https://raw.githubusercontent.com/junhoyeo/tokscale/main/packages/frontend/src/lib/publicProfileData.ts
- https://tokscale.ai/api/users/youranreus?period=week
- https://tokscale.ai/api/users/youranreus?period=month
- https://github.com/junhoyeo/tokscale/tree/main/.github/assets

## Period contract

- Official source lines 19–43 accepts only all/week/month, defaulting invalid or omitted period to all. There is no day period: do not send day or label all as day.
- Lines 55–89 define week as trailing 7 inclusive days and month as trailing 30 inclusive days. End anchor is the later of UTC today and latest submitted date, accommodating the submitting machine's timezone.
- Live week response: period=week, dateRange and chartRange 2026-08-29 through 2026-09-04, seven contribution days.
- Live month response: period=month, dateRange and chartRange 2026-08-06 through 2026-09-04.
- Use response dateRange directly; do not reproduce date arithmetic in the client.
- Lines 733–776 return scoped totalTokens, totalCost, inputTokens, outputTokens, cacheReadTokens, cacheWriteTokens, reasoningTokens, activeDays, user.rank, dateRange and period. Source these cards and breakdown values from stats. Rank is scoped upstream and may be null.
- Lines 608–618 restrict period contributions to the same date window. Aggregate these returned clients/models without filtering or local timezone conversion.
- all is intentionally not reinterpreted: totals are lifetime, while upstream activeDays uses its rolling chart window. Show returned activeDays unchanged.
- Five stats token components are present in live week and month responses. Never fabricate category amounts when fields are absent in a legacy cache; refresh incompatible snapshots.

## Client assets

Official assets directory lists 30 client-* files: amp, antigravity, cherrystudio, claude, codebuff, copilot, crush, cursor, devin, droid, freebuff, fx, gemini, goose, hermes, jcode, kilocode, kimi, mux, openai, openclaw, opencode, pi, qwen, roocode, sakana, senpi, synthetic, trae, zed. Formats include PNG, JPG and WebP. Verify the current list at implementation download time, preserve source attribution, and bundle compatible asset-catalog variants; codex maps to client-openai.

GitHub REST contents request returned HTTP 403 in this environment; the official HTML directory listing is readable and raw.githubusercontent.com downloads work with network approval. Use that documented fallback for asset inventory.

## Implementation inventory verification

The live GitHub HTML directory at commit a3209ff03da1b71262a4dd97bff854c07ca548b3 lists 31 client assets, adding client-hindsight.png to the previously cached 30-file list. All 31 were downloaded at that pinned revision with LICENSE; provenance is bundled in Resources/ClientOriginals/provenance.json. Zed has a PNG display copy and retains its original WebP.

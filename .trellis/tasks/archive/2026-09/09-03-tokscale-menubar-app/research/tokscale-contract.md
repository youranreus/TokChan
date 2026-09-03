# Tokscale CLI and public API research

Checked on 2026-09-03.

## Local CLI evidence

- `tokscale --version` reports `tokscale 4.15.0`.
- `tokscale submit --help` confirms `submit` plus client/date filters. It does not expose a flag that changes which Tokscale CLI version is executed.
- `tokscale whoami` reports the currently authenticated username as `youranreus`.
- The global `--json` option does not make `whoami` emit JSON in the installed version, so parsing its human-readable output would be a brittle identity contract.

## Upstream contract

- Official repository: https://github.com/junhoyeo/tokscale
- Official README documents `tokscale submit`, token-based non-interactive authentication, and `autosubmit` backed by `launchd` on macOS.
- `tokscale autosubmit status --json` is the machine-readable GUI integration boundary. The installed 4.15.0 CLI returns `enabled`, `intervalMinutes`, `scheduler`, client/date filters, `managedExecutable`, `managedExecutableVersion`, `managedExecutableStale`, `lastRunAtMs`, and `lastError`.
- Mutation commands are `autosubmit enable --interval <duration>` with optional client/date filters, `autosubmit disable`, and `autosubmit run --force`.
- Public profile data is served by `GET /api/users/:username`, with `period=all|month|week`. The route is public and returns aggregate totals, rank, breakdowns, and contribution data.
- Official source route: https://github.com/junhoyeo/tokscale/blob/main/packages/frontend/src/app/api/users/%5Busername%5D/route.ts

## Planning implications

- Keep submit execution and remote profile fetching as separate service boundaries so ordering and failure behavior are testable.
- Delegate scheduling entirely to Tokscale autosubmit. The app reads and mutates it through CLI commands; it does not directly edit `settings.json` or LaunchAgent files and does not maintain a competing submission timer.
- Treat username as an explicit app preference, optionally prefilled from `tokscale whoami`; do not parse or persist the API token.
- Product decision: the configured Tokscale version controls the package invoked through `npx --yes tokscale@<version> submit`; it is not merely a check against the globally installed executable.
- A Finder-launched macOS app cannot assume the user's interactive shell `PATH`, especially for NVM-installed Node binaries. CLI resolution must therefore be explicit and diagnosable.

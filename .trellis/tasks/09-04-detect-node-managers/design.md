# Design: Node manager-aware npx discovery

## Boundaries

Keep discovery inside `NpxLocator`; do not add shell execution or persistence. `DashboardViewModel` and `SettingsView` continue consuming the existing `NpxLocating.locate(preferredPath:)` contract. `ProcessRunner` keeps responsibility for prepending the selected executable directory to child `PATH`.

## Candidate pipeline

Build and evaluate candidates in this deterministic order:

1. Valid saved absolute override.
2. Inherited `PATH` entries.
3. Fixed system/package-manager paths.
4. Stable selected/default manager candidates in a fixed manager order.
5. Concrete installed versions from known manager roots, newest strict stable semantic version first.

Normalize and deduplicate candidate URLs while preserving first occurrence. Validate only the final candidate path with the existing regular executable checks.

## Manager adapters

Represent manager-specific layouts with small private candidate builders rather than recursive home scanning:

- **fnm**: absolute `FNM_DIR`, XDG/default and existing legacy roots; `aliases/default/bin/npx`, then `node-versions/v*/installation/bin/npx`.
- **Volta**: absolute `VOLTA_HOME` or `~/.volta`; supported `bin/npx` shim only.
- **asdf**: absolute `ASDF_DATA_DIR` or `~/.asdf`; exact home `.tool-versions` selection when safe, then `installs/nodejs/<semver>/bin/npx`; exclude shim.
- **mise**: absolute `MISE_INSTALLS_DIR`, otherwise absolute/default `MISE_DATA_DIR`; `installs/node/<semver>/bin/npx`; exclude shims and aliases from version sorting.
- **nodenv**: absolute `NODENV_ROOT` or `~/.nodenv`; exact global `version` selection, then `versions/<semver>/bin/npx`; exclude shim.
- **n**: absolute `N_PREFIX`, `/usr/local`, `~/n`, `~/.n`; inspect active `<prefix>/bin/npx` only.
- **nvm**: absolute `NVM_DIR`, XDG root when inherited, and `~/.nvm`; resolve only bounded exact-version default alias chains, then `versions/node/v<semver>/bin/npx`.

Environment root values must be absolute. Default-root lists are fixed and deduplicated. Directory enumeration is one level deep and bounded to known install containers.

## Version and config parsing

Add a private strict semantic-version value used only for candidate filtering and descending ordering. Accept an optional leading `v` and exactly three numeric components; prefer stable versions and ignore malformed/prerelease directories for fallback discovery. Config-file selection accepts one narrowly validated exact token and maps it only inside the known manager install root. NVM alias resolution is bounded and rejects separators, whitespace expressions, ranges, `system`, LTS labels and traversal tokens.

## Compatibility

No preference migration or protocol change. Existing explicit override, PATH, fixed-path and default NVM behavior remain, but malformed directory ordering becomes stricter. Users with custom roots absent from the GUI environment retain the manual override escape hatch.

## Safety and rollback

Discovery performs filesystem reads only and never invokes an executable. If a manager adapter is wrong, removing that adapter restores the prior pipeline without data migration. Focused fixtures must isolate real machine candidates through injected home, environment and fixed paths.

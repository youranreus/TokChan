# macOS `npx` discovery across Node version managers

Research date: 2026-09-04

## Executive recommendation

For a Finder-launched GUI app, discover executables from the filesystem; do not start a login/interactive shell, source profile files, or invoke a manager during discovery. Keep the existing high-level precedence:

1. valid saved absolute override;
2. inherited `PATH` (when the app was deliberately launched from a configured environment);
3. fixed system/package-manager candidates (`/opt/homebrew/bin/npx`, `/usr/local/bin/npx`, `/usr/bin/npx`);
4. stable manager defaults/active prefixes;
5. installed-version directories, newest valid stable semantic version first, only as a fallback.

Recommended MVP additions are **fnm**, **Volta**, **asdf**, **mise**, **nodenv**, **n**, and improved **nvm** default handling. Prefer a manager's stable default/active alias over “newest installed”; this better matches user intent. Direct installation paths are preferable to shell-dependent shims except for Volta, whose native shim is its supported stable execution boundary.

Every accepted `npx` must remain an existing, non-directory executable. The launcher must continue prepending the selected executable's sibling `bin` directory to child `PATH`, because normal `npx` files use `#!/usr/bin/env node` (confirmed on the local fnm installation, and already covered by project tests/spec).

## Finder-launched constraints

A GUI app launched through Finder/LaunchServices does not evaluate `.zshrc`, `.zprofile`, `.bashrc`, or manager activation snippets. Consequently variables such as `FNM_DIR`, `VOLTA_HOME`, `ASDF_DATA_DIR`, `MISE_DATA_DIR`, `NODENV_ROOT`, `N_PREFIX`, and `NVM_DIR` are usually absent even when the user configured them in a shell profile. The process `PATH` may likewise contain only system locations.

Discovery should therefore:

- honor an inherited manager-root environment variable when present and absolute;
- also inspect the manager's documented/default roots under the real user home;
- include documented legacy/default alternatives where applicable;
- never evaluate profile text to recover arbitrary environment assignments;
- never run `fnm env`, `mise activate`, `asdf exec`, `nodenv init`, `nvm.sh`, or a login shell merely to locate `npx`.

## Manager-by-manager findings

### fnm

**Stable roots and paths**

- `FNM_DIR` / `--fnm-dir` is the configurable installation root.
- Current fnm uses the XDG data root: `${XDG_DATA_HOME:-$HOME/.local/share}/fnm` on macOS in current source.
- Current source preserves existing legacy roots: `$HOME/.fnm`; on macOS it also recognizes an existing Apple data-directory root (`$HOME/Library/Application Support/fnm`).
- Installed Node trees are stable at:
  - `<FNM_DIR>/node-versions/v<version>/installation/bin/npx`
- Named aliases are directory symlinks under `<FNM_DIR>/aliases/`; specifically:
  - `<FNM_DIR>/aliases/default/bin/npx`

Local fnm 1.39.0 inspection confirmed `aliases/default` points to an `.../node-versions/v24.14.1/installation` directory and that `bin/npx` has `#!/usr/bin/env node`.

**Ephemeral path to avoid**

`fnm env` prepends a generated `<state-or-runtime-dir>/fnm_multishells/<session>/bin` path and sets `FNM_MULTISHELL_PATH`. This is per-shell/session state and may disappear; it is not a durable GUI discovery root. Current source chooses runtime, state, then cache storage for `fnm_multishells`.

**Version selection**

`fnm default` manages the `default` alias. `--use-on-cd` can switch versions from `.node-version`, `.nvmrc`, and optionally `package.json#engines`; that shell behavior is unavailable to Finder without evaluating `fnm env`. For TokChan's manager fallback, use `aliases/default/bin/npx` first, then scan concrete `node-versions/v*/installation/bin/npx` entries by semantic version.

**MVP**: yes; this is the primary reported gap.

### Volta

**Stable root and path**

- `VOLTA_HOME` is configurable; Unix default is `$HOME/.volta`.
- `$VOLTA_HOME/bin` is explicitly the directory added to `PATH` by Volta setup.
- `$VOLTA_HOME/bin/npx` is a native Volta shim and is the stable public execution path.
- Internal downloaded Node images live below `$VOLTA_HOME/tools/image/node/<version>/bin`, but this layout is an implementation detail and should not be scanned for MVP discovery.

**Version selection**

Volta's shim chooses a project-pinned toolchain according to current directory, otherwise the user's default toolchain. Official docs describe the default as the version used outside pinned projects and project pins as data stored in `package.json`. This behavior is precisely what the shim is designed to preserve.

TokChan currently does not set `Process.currentDirectoryURL`; therefore shim selection can depend on the GUI process's inherited working directory. It should not be assumed to represent the user's shell project. Nevertheless, outside a pinned project the shim gives Volta's configured default and is more faithful than selecting an internal image by version number.

**Risk/performance**

The shim dispatches through Volta and is slower than a direct Node-tree script, but avoids reverse-engineering Volta's internal default metadata. Validate `$VOLTA_HOME/bin/npx` only; do not recursively scan caches/images.

**MVP**: yes, via the stable shim only.

### asdf

**Stable roots and paths**

- `ASDF_DATA_DIR` contains plugins, shims, and installs and must be absolute.
- Current documented default is `$HOME/.asdf` when it exists, otherwise `ASDF_DIR`; the normal legacy/default user layout is `$HOME/.asdf`.
- Node installations from `asdf-nodejs` are conventionally:
  - `<ASDF_DATA_DIR>/installs/nodejs/<version>/bin/npx`
- Shim:
  - `<ASDF_DATA_DIR>/shims/npx`

**Why the shim is unsafe/unreliable for this GUI MVP**

Current asdf source generates the shim as `#!/usr/bin/env bash` followed by `exec asdf exec "npx" "$@"`. An absolute call to the shim still requires both `bash` and `asdf` to be resolvable through child `PATH`. TokChan only prepends the shim directory; Finder's `PATH` may not contain the asdf binary. The shim also resolves versions from current-directory `.tool-versions` configuration, which is ambiguous for a GUI app.

**Version selection**

asdf normally resolves `.tool-versions` in the current directory/parents; `asdf set -u` writes a home-level default. Environment variable `ASDF_NODEJS_VERSION` can override it, but is shell-local and usually absent in Finder launches. Parsing every asdf version form (`system`, multiple fallbacks, `ref:`, `path:`) is too broad for MVP.

Recommended MVP: if a simple home `$HOME/.tool-versions` `nodejs <exact-semver>` points to an executable installation, prefer it; otherwise scan only concrete exact-semver install directories and choose newest. Ignore `path:`/`ref:` and malformed/traversal-shaped values. Do not invoke the asdf shim.

**MVP**: yes, direct installs; simple global exact-version preference is desirable but may be deferred if it complicates the locator.

### mise

**Stable roots and paths**

- `MISE_DATA_DIR` override; default `${XDG_DATA_HOME:-$HOME/.local/share}/mise`.
- `MISE_INSTALLS_DIR` can independently override installs.
- Default Node installations:
  - `<MISE_INSTALLS_DIR or MISE_DATA_DIR/installs>/node/<version>/bin/npx`
- mise creates stable symlinks for version prefixes and matching aliases such as `20`, `20.15`, `lts`, and `latest` beneath `.../installs/node/`.
- Default shim is `<MISE_DATA_DIR>/shims/npx`; `MISE_SHIMS_DIR` can override it.

**Version selection**

`mise activate` puts selected real installation directories on `PATH`; selection can merge `mise.toml`, `.tool-versions`, idiomatic files, environment, and directory hierarchy. Shims are recommended by mise for IDE/non-interactive contexts and dynamically load the current context.

**Risk/performance**

The shim is project/current-directory aware, adds dispatch overhead, and mise's documented lazy shims can install a configured provider on first invocation. Automatic network/install side effects are inappropriate for a locator whose job is only to find an already-installed `npx`. Direct installation paths avoid those side effects. Alias `latest` is stable as a path but is not necessarily the user's globally selected version; it is only a better fallback than an arbitrary lexical directory.

Recommended MVP: inspect absolute inherited overrides plus default install root, ignore `shims/npx`, prefer an executable exact target from an unambiguous stable alias only if product requirements choose that policy, otherwise scan concrete exact-semver directories newest-first. Do not follow prefix aliases as duplicate “versions” during sorting.

**MVP**: yes, direct installs; shim support deferred.

### nodenv

**Stable roots and paths**

- `NODENV_ROOT` override; default `$HOME/.nodenv`.
- Installations: `<NODENV_ROOT>/versions/<version>/bin/npx`.
- Global/default selection is written to `<NODENV_ROOT>/version`.
- Shim: `<NODENV_ROOT>/shims/npx`.

**Version selection**

Precedence is shell `NODENV_VERSION`, nearest `.node-version`, then global `<NODENV_ROOT>/version`; `system` delegates to `PATH`. In Finder, shell selection is normally absent and current-directory selection is not meaningful, so a simple exact version from the global file is the best user-intent signal. Fall back to concrete exact-semver version directories newest-first.

**Why not the shim**

The shim requires nodenv's dispatch environment/binary and is current-directory aware. Direct installation is more robust in a GUI, and TokChan's child `PATH` fix supplies sibling `node` for the `npx` shebang.

Reject `system`, multiple values, paths, and malformed version-file contents when mapping the global file to a filesystem child.

**MVP**: yes, direct global version then installed scan.

### n

**Stable active prefix**

`n` differs from multi-version shim managers: it installs one active Node into a prefix and keeps downloaded versions in a cache.

- Default active prefix: `/usr/local`; executable `/usr/local/bin/npx` (already covered).
- `N_PREFIX` overrides the active prefix; executable `$N_PREFIX/bin/npx`.
- Official `n-install` sets `N_PREFIX=$HOME/n`, making `$HOME/n/bin/npx` a common stable path.
- The README also uses `$HOME/.n` as a custom-prefix example.
- Cached versions under `<prefix>/n/versions` are not the active installation and should not be scanned.

**Version selection**

`n` overwrites the active prefix when switching. Therefore `<prefix>/bin/npx` is already the selected version and no version sorting is needed.

**MVP**: yes: inherited absolute `N_PREFIX`, `/usr/local/bin/npx`, `$HOME/n/bin/npx`, and optionally `$HOME/.n/bin/npx`. The `/usr/local` candidate remains in the fixed system stage; home prefixes belong in the manager stage.

### nvm

**Stable roots and paths**

- `NVM_DIR` is configurable. The official profile snippet defaults to `$HOME/.nvm`, or `$XDG_CONFIG_HOME/nvm` when XDG config is set.
- Modern Node installations:
  - `<NVM_DIR>/versions/node/v<version>/bin/npx`
- nvm is a sourced shell function, not an executable; running it requires sourcing `nvm.sh` and is out of scope.
- User aliases are text files under `<NVM_DIR>/alias/`; `alias/default` may contain another alias or a version/range, so it is not a direct symlink.

**Version selection**

A shell may select `.nvmrc`, an explicit `nvm use`, or the `default` alias. Current TokChan ignores the default alias and chooses numerically newest installed. A safe improvement is to resolve only a bounded alias chain whose tokens are tightly validated and that ends in one installed exact version. Do not implement the full nvm range/LTS resolver in MVP. If no safely resolvable exact default exists, retain newest concrete stable semantic version fallback.

Inspect both an inherited absolute `NVM_DIR` and conventional `$HOME/.nvm`; inspect `${XDG_CONFIG_HOME}/nvm` only when `XDG_CONFIG_HOME` is inherited and absolute. Guessing arbitrary shell-configured roots is impossible without profile evaluation.

**MVP**: already partial; add safe exact-default preference and configurable/default roots if feasible.

## Recommended MVP compatibility matrix

| Manager/install style | Candidate(s) | Root source | Selection behavior | MVP | Notes |
|---|---|---|---|:---:|---|
| Existing override | saved absolute `npx` | preference | exact user choice | Yes | Always first if executable |
| Inherited shell / Homebrew / system | `PATH/npx`, `/opt/homebrew/bin/npx`, `/usr/local/bin/npx`, `/usr/bin/npx` | process/fixed | inherited or package-manager active | Yes | Preserve current precedence/tests |
| fnm | `aliases/default/bin/npx`; then `node-versions/v*/installation/bin/npx` | absolute `FNM_DIR`; XDG default; existing `.fnm`; existing Apple legacy root | configured default, else newest exact stable semver | Yes | Never use `fnm_multishells` |
| Volta | `bin/npx` | absolute `VOLTA_HOME`; `$HOME/.volta` | Volta default/project-aware shim | Yes | Native stable shim; no image scan |
| asdf | `installs/nodejs/<version>/bin/npx` | absolute `ASDF_DATA_DIR`; `$HOME/.asdf` | simple global exact version if supported, else newest exact stable semver | Yes | Do not use shell shim |
| mise | `installs/node/<version>/bin/npx` | absolute `MISE_INSTALLS_DIR`; otherwise absolute/default `MISE_DATA_DIR` | newest concrete exact stable semver (or explicit documented alias by product policy) | Yes | Do not invoke lazy/project-aware shim |
| nodenv | `versions/<version>/bin/npx` | absolute `NODENV_ROOT`; `$HOME/.nodenv` | exact global file, else newest exact stable semver | Yes | Ignore `system` global token |
| n | `<prefix>/bin/npx` | absolute `N_PREFIX`; `/usr/local`; `$HOME/n`; optional `$HOME/.n` | single active installation | Yes | Never scan cache |
| nvm | `versions/node/v<version>/bin/npx` | absolute `NVM_DIR`; `$HOME/.nvm`; inherited absolute XDG root | safely resolvable exact default, else newest exact stable semver | Yes | Existing locator already scans default root |
| Arbitrary custom roots only present in shell profiles | unknown | profile evaluation required | unknown | No | Manual override is recovery path |
| asdf/mise/nodenv generic shims | manager shim | configurable shim roots | dynamic by cwd/config | No | Shell/binary dependency, side effects, ambiguity |
| fnm multishell links | state/runtime `fnm_multishells/*` | ephemeral shell state | last per-shell `fnm use` | No | Stale/temporary |

## Suggested detailed precedence within manager discovery

After existing fixed candidates:

1. stable selected/default candidates that can execute without shell setup:
   - fnm `aliases/default/bin/npx`;
   - Volta `$VOLTA_HOME/bin/npx`;
   - n active prefixes;
   - nodenv exact global direct install;
   - nvm safely resolved exact default direct install;
   - optionally asdf simple home-global exact direct install;
2. concrete installed-version scans, manager order fixed in code (not dependent on directory enumeration), each manager newest exact stable semver first.

There is no universally correct ordering between different managers installed simultaneously. A fixed documented order is deterministic, but users with multiple active managers should rely on inherited `PATH` or the saved override. Avoid trying to infer “most recently used” from mtimes.

## Security and performance requirements

1. **No code execution during discovery.** Do not run shells, managers, shims for probing, profile files, or `npx --version`. `npx` itself can fetch packages, and mise lazy shims can install tools.
2. **Absolute roots only.** Environment root overrides must be absolute, normalized filesystem paths. Empty/relative values are ignored.
3. **Treat config/alias text as untrusted.** Accept only narrowly defined exact-version tokens before joining paths. Reject `/`, `..`, NUL, whitespace/multiple tokens where unsupported, shell syntax, `path:`, `ref:`, and `system` unless explicitly handled.
4. **Bound traversal.** Enumerate only one known versions directory level; no recursive home scans. Ignore hidden/download/cache directories and aliases when sorting concrete versions.
5. **Deterministic semantic ordering.** Parse strict versions rather than mapping malformed components to zero. Prefer stable releases over prereleases unless prerelease support is deliberately specified. The current NVM parser (`Int(component) ?? 0`, lexical tie-break) can rank malformed names and should not be generalized unchanged.
6. **Symlinks.** Stable manager aliases are expected symlinks. Follow only the final candidate needed for executable validation; broken aliases fail normally. Do not use alias targets to recursively discover unrelated paths.
7. **Regular executable validation.** Preserve `fileExists`, not-directory, and executable checks. If stronger hardening is desired, explicitly decide whether symlink-to-file is allowed (it must be allowed for normal manager aliases/shims).
8. **Do not trust freshness metadata.** Directory mtimes do not represent active manager choice.
9. **Avoid filesystem explosion.** Candidate roots are a small fixed list; deduplicate normalized candidate paths while preserving precedence.
10. **Launcher compatibility.** Continue prepending the selected candidate's directory to child `PATH`. Direct installation `npx` scripts need sibling `node`; generic manager shims may need other binaries and are therefore mostly excluded.

## Existing implementation/spec/test assessment

### `TokChan/Shared/Services/NpxLocator.swift`

Current behavior:

- valid absolute preferred path;
- every inherited `PATH` entry + `/npx`;
- injected/default fixed candidates (`/opt/homebrew`, `/usr/local`, `/usr/bin`);
- direct children of `$HOME/.nvm/versions/node`, sorted by a permissive three-integer parser;
- first existing executable non-directory candidate.

Gaps:

- only default-root nvm is recognized;
- nvm configured default is ignored;
- no fnm, Volta, asdf, mise, nodenv, or home-prefix `n` discovery;
- malformed/prerelease version directory ordering is not strict semver;
- no candidate deduplication (minor performance issue);
- no manager roots are injectable independently for focused tests, so implementation may benefit from a pure candidate-builder/root abstraction.

### `TokChanTests/NpxLocatorTests.swift`

Existing tests cover preferred-path precedence/fallback, nil, inherited PATH before fixed candidate, fixed candidate before NVM, numeric NVM newest selection, relative override rejection, and executable fixture creation.

Recommended additions:

- one default-root and one custom-root fixture per manager;
- fnm default alias before newer installed version;
- fnm legacy/XDG roots and explicit exclusion of multishell state;
- Volta shim candidate and precedence;
- asdf/mise/nodenv direct layout cases, plus shim exclusion where intentional;
- nodenv global exact selection and malformed/`system` fallback;
- `n` active `$HOME/n` and injected `N_PREFIX` cases; no cache scan;
- nvm exact default alias, bounded alias chain, malformed/traversal alias fallback, and custom `NVM_DIR`;
- strict semver ordering (`v9` vs `v22`, prerelease vs release, malformed directories ignored);
- broken alias, directory named `npx`, and non-executable file rejection;
- deterministic cross-manager precedence and duplicate candidates;
- environment root values that are empty/relative are ignored;
- retain injection/clearing of fixed system candidates so developer/CI machines cannot leak real tools into tests.

### Relevant project specification

`.trellis/spec/macos/tokscale-integration.md` currently codifies override → inherited PATH → fixed candidates → newest NVM and requires sibling-bin PATH prepending. This task will require that contract and its locator test matrix to be updated during implementation, but this research agent did not edit specs.

## Sources

Official documentation and upstream source were preferred because several managers do not document every on-disk detail.

- fnm command/config docs (`FNM_DIR`, defaults, version strategy): https://github.com/Schniz/fnm/blob/master/docs/commands.md and https://github.com/Schniz/fnm/blob/master/docs/configuration.md
- fnm directory/source layout (XDG/legacy roots, multishell storage): https://github.com/Schniz/fnm/blob/master/src/directories.rs
- fnm installation/alias layout: https://github.com/Schniz/fnm/blob/master/src/config.rs, https://github.com/Schniz/fnm/blob/master/src/version.rs, https://github.com/Schniz/fnm/blob/master/src/alias.rs
- Volta getting started (`VOLTA_HOME`, `$VOLTA_HOME/bin`, default Node): https://docs.volta.sh/guide/getting-started
- Volta behavior and project/default selection: https://docs.volta.sh/guide/understanding
- Volta Unix default and layout source: https://github.com/volta-cli/volta/blob/main/crates/volta-core/src/layout/unix.rs and https://github.com/volta-cli/volta/blob/main/crates/volta-layout/src/v4.rs
- asdf configuration (`ASDF_DATA_DIR`, `.tool-versions`): https://asdf-vm.com/manage/configuration.html and source https://github.com/asdf-vm/asdf/blob/master/docs/manage/configuration.md
- asdf shim generation (`#!/usr/bin/env bash`, `asdf exec`): https://github.com/asdf-vm/asdf/blob/master/internal/shims/shims.go
- mise directories (`MISE_DATA_DIR`, installs, aliases, shims): https://mise.jdx.dev/directories.html and source https://github.com/jdx/mise/blob/main/docs/directories.md
- mise shims, lazy behavior, non-interactive guidance, performance: https://mise.jdx.dev/dev-tools/shims.html
- nodenv README (roots, selection precedence, shims, versions): https://github.com/nodenv/nodenv/blob/master/README.md
- nodenv direct resolution implementation: https://github.com/nodenv/nodenv/blob/master/libexec/nodenv-prefix and https://github.com/nodenv/nodenv/blob/master/libexec/nodenv-which
- n README (active prefix, cache, `N_PREFIX`, `n-install`): https://github.com/tj/n/blob/master/README.md
- nvm README (`NVM_DIR`, XDG default, sourced function): https://github.com/nvm-sh/nvm/blob/master/README.md
- nvm installation and alias implementation: https://github.com/nvm-sh/nvm/blob/master/nvm.sh
- npm `npx` behavior and install/network implications: https://docs.npmjs.com/cli/v11/commands/npx
- Existing project files inspected: `TokChan/Shared/Services/NpxLocator.swift`, `TokChanTests/NpxLocatorTests.swift`, `.trellis/spec/macos/tokscale-integration.md`, and archived task `.trellis/tasks/archive/2026-09/09-04-auto-detect-npx/prd.md`.

## Research caveat

`python3 ./.trellis/scripts/task.py current --source` was attempted first as required, but the repository script currently fails to import because `.trellis/scripts/common/task_context.py:240` has an unterminated Python string literal. The delegated task context explicitly identified `.trellis/tasks/09-04-detect-node-managers`, which was used as the research destination. No file outside this task's `research/` directory was modified.

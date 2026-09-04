# 优化发布脚本

## Goal

简化本地发布准备流程：支持选择 patch、minor 或 major 版本递增，并移除本地脚本对 GitHub CLI (`gh`) 的依赖，使维护者只需 Git 和 Python 即可创建发布提交与 Tag。

## Background and Confirmed Facts

- `scripts/release.sh` 当前只接受 `patch [--push]`，将 `X.Y.Z` 更新为 `X.Y.(Z+1)`，构建号始终加一。
- 本地脚本使用 `git` 完成分支、同步状态、Tag 冲突、提交、annotated Tag 和原子推送等操作。
- 本地脚本使用 `gh` 的唯一目的，是预先检查认证、仓库访问权限及目标 GitHub Release 是否已存在；这些不是 Git 操作。
- `.github/workflows/release.yml` 在 Tag 推送后负责通过 GitHub API 创建、上传并发布 GitHub Release；这一过程无法仅靠 Git 完成，因此 CI 中的 `gh` 保留。
- CI 已对现有 draft Release 做续传，并拒绝覆盖已发布 Release；移除本地 Release 预检后，远端异常仍会在 CI 发布阶段失败关闭。

## Requirements

- `scripts/release.sh` 接受 `patch`、`minor` 和 `major` 三种版本更新类型，并继续支持可选的 `--push`。
- `patch` 将 `X.Y.Z` 更新为 `X.Y.(Z+1)`；`minor` 将其更新为 `X.(Y+1).0`；`major` 将其更新为 `(X+1).0.0`。
- 三种发布类型都将 `CURRENT_PROJECT_VERSION` 加一，并沿用现有构建、确认、提交、annotated Tag 与可选原子推送流程。
- 本地发布脚本不再要求安装或认证 `gh`，也不再查询 GitHub Release API。
- 保留基于 `git` 的本地和远端 Tag 冲突检查、clean tree、`master` 与 `origin/master` 同步等安全门禁。
- 更新发布脚本测试和发布规范，使接口与职责边界保持一致。

## Acceptance Criteria

- [x] `scripts/release.sh minor` 能从测试版本 `7.8.9` 生成 `7.9.0`，构建号从 `42` 更新为 `43`，并创建对应发布提交与 annotated Tag `v7.9.0`。
- [x] `scripts/release.sh major` 能从测试版本 `7.8.9` 生成 `8.0.0`，构建号从 `42` 更新为 `43`，并创建对应发布提交与 annotated Tag `v8.0.0`。
- [x] 现有 `scripts/release.sh patch` 行为保持不变。
- [x] `scripts/release.sh` 在 PATH 中没有 `gh` 时仍能完成本地发布准备。
- [x] 本地脚本不包含 `gh` 调用；GitHub Actions 中用于发布 GitHub Release 的 `gh` 调用保持不变。
- [x] 无效版本更新类型仍以 usage 错误退出。
- [x] 发布脚本的现有 Git 安全门禁继续通过自动化测试。
- [x] `bash -n scripts/release.sh tests/test_release_scripts.sh`、`python3 tests/test_project_version.py` 与 `bash tests/test_release_scripts.sh` 通过。

## Out of Scope

- 不用纯 Git 重写 GitHub Actions 的 Release 发布逻辑；GitHub Release 是托管平台 API 资源，不是 Git 对象。
- 不增加 prerelease 或自定义目标版本支持。
- 不改变产物格式、签名/公证策略、CI 触发条件或已发布 Release 的不可覆盖策略。

## Risks and Deferred Items

- 去掉本地 GitHub Release API 预检后，极端情况下（例如有人手工创建了与尚不存在 Tag 同名的 Release）冲突会延后到 GitHub Actions 阶段发现；该取舍用于换取本地零 `gh` 依赖，并由 CI 的失败关闭逻辑兜底。

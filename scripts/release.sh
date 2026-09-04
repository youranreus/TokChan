#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/release.sh patch [--push]" >&2
}

fail() {
  echo "release: $*" >&2
  exit 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

[[ $# -ge 1 && "$1" == patch ]] || { usage; exit 2; }
shift
push_release=false
if (($#)); then
  [[ $# -eq 1 && "$1" == --push ]] || { usage; exit 2; }
  push_release=true
fi

for command_name in git gh python3; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done
[[ -x scripts/build-release.sh ]] || fail "scripts/build-release.sh is not executable"
[[ -f TokChan.xcodeproj/project.pbxproj ]] || fail "TokChan project file was not found"

project_file=TokChan.xcodeproj/project.pbxproj
version_changed=false
release_committed=false
tag_created=false
target_tag=""

recovery() {
  local status=$?
  if [[ $status -eq 0 ]]; then
    return
  fi
  echo >&2
  echo "release: stopped without destructive cleanup." >&2
  if $tag_created; then
    echo "Inspect the local Tag with: git show $target_tag" >&2
    echo "If it was never pushed and must be corrected: git tag -d $target_tag" >&2
  elif $release_committed; then
    echo "The release commit exists but its Tag was not created. Inspect it before continuing." >&2
  elif $version_changed; then
    echo "Inspect the version edit with: git diff -- $project_file" >&2
    echo "To discard only that uncommitted edit: git restore -- $project_file" >&2
  fi
}
trap recovery EXIT

[[ -z "$(git status --porcelain)" ]] || fail "working tree and index must be clean"
branch=$(git symbolic-ref --quiet --short HEAD) || fail "HEAD must be on branch master"
[[ "$branch" == master ]] || fail "releases must be prepared from master (current: $branch)"

echo "==> Fetching origin/master and Tags"
git fetch origin master --tags
remote_master=$(git rev-parse --verify refs/remotes/origin/master 2>/dev/null) || \
  fail "origin/master does not exist"
head_commit=$(git rev-parse HEAD)
[[ "$head_commit" == "$remote_master" ]] || \
  fail "HEAD must exactly match origin/master before releasing"
[[ -z "$(git status --porcelain)" ]] || fail "working tree changed while checking release prerequisites"

gh auth status >/dev/null || fail "GitHub CLI is not authenticated"
# Resolve repository access up front so network/auth/permission failures cannot look like absence.
gh repo view --json nameWithOwner >/dev/null || fail "cannot access the GitHub repository with gh"

read -r current_version current_build < <(
  python3 scripts/lib/project-version.py "$project_file" get
)
IFS=. read -r major minor patch_number <<<"$current_version"
[[ "$current_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail "current marketing version is not stable SemVer: $current_version"
[[ "$current_build" =~ ^[1-9][0-9]*$ ]] || \
  fail "current build number is not a positive integer: $current_build"
next_version="$major.$minor.$((10#$patch_number + 1))"
next_build="$((10#$current_build + 1))"
target_tag="v$next_version"

if git show-ref --verify --quiet "refs/tags/$target_tag"; then
  fail "local Tag already exists: $target_tag"
fi
set +e
remote_tag_output=$(git ls-remote --exit-code --tags origin "refs/tags/$target_tag" 2>&1)
remote_tag_status=$?
set -e
case $remote_tag_status in
  0) fail "remote Tag already exists: $target_tag" ;;
  2) ;;
  *) fail "could not check remote Tag $target_tag: $remote_tag_output" ;;
esac

set +e
release_output=$(gh api --paginate "repos/{owner}/{repo}/releases?per_page=100" \
  --jq ".[] | select(.tag_name == \"$target_tag\") | .id" 2>&1)
release_status=$?
set -e
[[ $release_status -eq 0 ]] || \
  fail "could not check whether GitHub Release $target_tag exists: $release_output"
[[ -z "$release_output" ]] || fail "a GitHub Release already exists for $target_tag"

echo "==> Updating $current_version ($current_build) to $next_version ($next_build)"
python3 scripts/lib/project-version.py "$project_file" set \
  --marketing "$next_version" \
  --build "$next_build" >/dev/null
version_changed=true
read -r verified_version verified_build < <(
  python3 scripts/lib/project-version.py "$project_file" get
)
[[ "$verified_version" == "$next_version" && "$verified_build" == "$next_build" ]] || \
  fail "version update did not verify"

echo "==> Testing and packaging $target_tag"
scripts/build-release.sh

echo
 echo "==> Version diff"
git --no-pager diff -- "$project_file"
echo
printf "Create release commit and annotated Tag %s? Type 'yes' to continue: " "$target_tag"
read -r confirmation
[[ "$confirmation" == yes ]] || fail "confirmation not received; version edit was left in place"

# The tested source must still be exactly HEAD plus the authoritative version edit.
[[ "$(git rev-parse HEAD)" == "$head_commit" ]] || \
  fail "HEAD changed while the release build was running"
[[ -z "$(git diff --cached --name-only)" ]] || \
  fail "unexpected staged changes appeared while the release build was running"
changed_paths=$(git diff --name-only)
[[ "$changed_paths" == "$project_file" ]] || \
  fail "unexpected tracked changes appeared while the release build was running: $changed_paths"
untracked_paths=$(git ls-files --others --exclude-standard)
[[ -z "$untracked_paths" ]] || \
  fail "unexpected untracked files appeared while the release build was running: $untracked_paths"

# The clean-tree precondition plus the checks above keep unrelated files out of the release commit.
git add -- "$project_file"
staged_paths=$(git diff --cached --name-only)
[[ "$staged_paths" == "$project_file" ]] || fail "unexpected paths are staged: $staged_paths"
git commit -m "chore(release): $target_tag" -- "$project_file"
release_committed=true
git tag -a "$target_tag" -m "TokChan $target_tag"
tag_created=true

if $push_release; then
  echo "WARNING: pushing $target_tag triggers the GitHub publication workflow."
  printf "Type 'push' to atomically push the release commit and Tag: "
  read -r push_confirmation
  [[ "$push_confirmation" == push ]] || fail "push confirmation not received; commit and Tag remain local"
  git push --atomic origin HEAD "refs/tags/$target_tag"
  echo "Pushed $target_tag. Monitor the GitHub Actions release workflow."
else
  echo "Created local release commit and annotated Tag $target_tag."
  echo "Review them, then trigger publication with:"
  echo "  git push --atomic origin HEAD refs/tags/$target_tag"
fi

#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/tokchan-script-tests.XXXXXX")
trap 'rm -rf -- "$test_tmp"' EXIT
mkdir -p "$test_tmp/tmp"
export TMPDIR="$test_tmp/tmp"

fixture_version=7.8.9
fixture_build=42
patch_version=7.8.10
minor_version=7.9.0
major_version=8.0.0
next_build=43
fixture_asset="TokChan-v${fixture_version}-macos-universal.zip"
next_tag="v${patch_version}"
export TEST_FIXTURE_VERSION=$fixture_version
export TEST_FIXTURE_BUILD=$fixture_build

pass_count=0
pass() {
  pass_count=$((pass_count + 1))
  echo "ok $pass_count - $1"
}

expect_failure() {
  local expected=$1
  shift
  local output status
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  [[ $status -ne 0 ]] || { echo "expected failure: $*" >&2; exit 1; }
  [[ "$output" == *"$expected"* ]] || {
    echo "missing expected error '$expected' in:" >&2
    echo "$output" >&2
    exit 1
  }
}

expect_status_failure() {
  local expected_status=$1
  local expected=$2
  shift 2
  local output status
  set +e
  output=$("$@" 2>&1)
  status=$?
  set -e
  [[ $status -eq $expected_status ]] || {
    echo "expected status $expected_status, got $status: $*" >&2
    echo "$output" >&2
    exit 1
  }
  [[ "$output" == *"$expected"* ]] || {
    echo "missing expected error '$expected' in:" >&2
    echo "$output" >&2
    exit 1
  }
}

expect_failure "unknown argument" "$root/scripts/build-release.sh" --unknown
pass "build script rejects unknown arguments"
expect_failure "only be specified once" "$root/scripts/build-release.sh" --skip-tests --skip-tests
pass "build script rejects duplicate arguments"
expect_status_failure 2 "Usage: scripts/release.sh {patch|minor|major} [--push]" \
  "$root/scripts/release.sh" invalid
pass "release script rejects an invalid version update type with usage status"

make_build_fixture() {
  local fixture=$1
  mkdir -p "$fixture/scripts/lib" "$fixture/TokChan.xcodeproj/xcshareddata/xcschemes" "$fixture/mock-bin"
  cp "$root/scripts/build-release.sh" "$fixture/scripts/"
  cp "$root/scripts/lib/project-version.py" "$fixture/scripts/lib/"
  cp "$root/TokChan.xcodeproj/project.pbxproj" "$fixture/TokChan.xcodeproj/"
  python3 "$fixture/scripts/lib/project-version.py" \
    "$fixture/TokChan.xcodeproj/project.pbxproj" set \
    --marketing "$fixture_version" --build "$fixture_build" >/dev/null
  cp "$root/TokChan.xcodeproj/xcshareddata/xcschemes/TokChan.xcscheme" \
    "$fixture/TokChan.xcodeproj/xcshareddata/xcschemes/"
  cat > "$fixture/mock-bin/xcrun" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
  cat > "$fixture/mock-bin/lipo" <<'MOCK'
#!/usr/bin/env bash
echo 'arm64 x86_64'
MOCK
  cat > "$fixture/mock-bin/codesign" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

record() {
  [[ -z "${MOCK_CODESIGN_LOG:-}" ]] || printf '%s\n' "$1" >> "$MOCK_CODESIGN_LOG"
}

if [[ $# -eq 6 && "$1" == --force && "$2" == --sign && "$3" == - && \
      "$4" == --identifier ]]; then
  identifier=$5
  app=$6
  [[ "$identifier" == com.youranreus.TokChan ]] || exit 64
  record "$(printf 'sign\t%s\t%s' "$identifier" "$app")"
  [[ "${MOCK_CODESIGN_SIGN_FAILURE:-}" != 1 ]] || exit 1
  mkdir -p "$app/Contents/_CodeSignature"
  printf 'fixture bundle signature\n' > "$app/Contents/_CodeSignature/CodeResources"
  exit 0
fi

if [[ $# -eq 5 && "$1" == --verify && "$2" == --deep && "$3" == --strict && \
      "$4" == --verbose=2 ]]; then
  app=$5
  record "$(printf 'verify\t%s' "$app")"
  [[ -f "$app/Contents/_CodeSignature/CodeResources" ]] || exit 1
  if [[ "$app" == */verification/TokChan.app ]]; then
    [[ "${MOCK_CODESIGN_POST_VERIFY_FAILURE:-}" != 1 ]] || exit 1
  else
    [[ "${MOCK_CODESIGN_PRE_VERIFY_FAILURE:-}" != 1 ]] || exit 1
  fi
  exit 0
fi

if [[ $# -eq 3 && "$1" == -dv && "$2" == --verbose=4 ]]; then
  app=$3
  record "$(printf 'display\t%s' "$app")"
  [[ -f "$app/Contents/_CodeSignature/CodeResources" ]] || exit 1
  [[ "${MOCK_CODESIGN_METADATA_FAILURE:-}" != 1 ]] || exit 1
  identifier=${MOCK_CODESIGN_METADATA_IDENTIFIER:-com.youranreus.TokChan}
  if [[ "$app" == */verification/TokChan.app ]]; then
    [[ "${MOCK_CODESIGN_POST_METADATA_FAILURE:-}" != 1 ]] || exit 1
    identifier=${MOCK_CODESIGN_POST_METADATA_IDENTIFIER:-$identifier}
  fi
  printf '%s\n' \
    "Identifier=$identifier" \
    'Signature=adhoc' \
    'Info.plist entries=3' \
    'TeamIdentifier=not set' \
    'Sealed Resources version=2 rules=13 files=2' >&2
  if [[ "${MOCK_CODESIGN_DUPLICATE_IDENTIFIER:-}" == 1 ]]; then
    printf 'Identifier=%s\n' "$identifier" >&2
  fi
  exit 0
fi

echo "unexpected codesign invocation: $*" >&2
exit 64
MOCK
  cat > "$fixture/mock-bin/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ " $* " == *" -version "* ]]; then
  printf 'Xcode 26.6\nBuild version TEST\n'
  exit 0
fi
if [[ " $* " == *" -showBuildSettings "* ]]; then
  configuration=Debug
  for ((index=1; index <= $#; index++)); do
    if [[ "${!index}" == -configuration ]]; then
      next=$((index + 1)); configuration=${!next}
    fi
  done
  version=${TEST_FIXTURE_VERSION:?}
  [[ "$configuration" == Release && "${MOCK_RELEASE_DRIFT:-}" == 1 ]] && version=7.8.99
  printf '    MARKETING_VERSION = %s\n    CURRENT_PROJECT_VERSION = %s\n' \
    "$version" "${TEST_FIXTURE_BUILD:?}"
  exit 0
fi
if [[ "$1" == test ]]; then
  exit 0
fi
if [[ "$1" == build ]]; then
  derived=''
  for ((index=1; index <= $#; index++)); do
    if [[ "${!index}" == -derivedDataPath ]]; then
      next=$((index + 1)); derived=${!next}
    fi
  done
  app="$derived/Build/Products/Release/TokChan.app"
  mkdir -p "$app/Contents/MacOS"
  printf 'fake executable' > "$app/Contents/MacOS/TokChan"
  chmod +x "$app/Contents/MacOS/TokChan"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>${TEST_FIXTURE_VERSION:?}</string>
<key>CFBundleVersion</key><string>${TEST_FIXTURE_BUILD:?}</string>
<key>CFBundleIdentifier</key><string>com.youranreus.TokChan</string>
</dict></plist>
PLIST
  exit 0
fi
echo "unexpected xcodebuild invocation: $*" >&2
exit 1
MOCK
  chmod +x "$fixture/scripts/build-release.sh" "$fixture/scripts/lib/project-version.py" "$fixture/mock-bin/"*
}

fixture="$test_tmp/build"
make_build_fixture "$fixture"
zip="$fixture/output/$fixture_asset"
checksum="$zip.sha256"

assert_no_build_assets() {
  [[ ! -e "$zip" && ! -L "$zip" && ! -e "$checksum" && ! -L "$checksum" ]]
}

expect_failure "ad-hoc bundle signing failed" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_SIGN_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when ad-hoc bundle signing fails"

rm -rf "$fixture/output"
expect_failure "strict signature verification failed" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_PRE_VERIFY_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when pre-package signature verification fails"

rm -rf "$fixture/output"
expect_failure "unexpected identifier wrong.identifier" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_METADATA_IDENTIFIER=wrong.identifier \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when signature metadata has the wrong identifier"

rm -rf "$fixture/output"
expect_failure "could not inspect signature metadata" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_METADATA_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when signature metadata inspection fails"

rm -rf "$fixture/output"
expect_failure "exactly one Identifier" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_DUPLICATE_IDENTIFIER=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects ambiguous duplicate signature metadata"

rm -rf "$fixture/output"
expect_failure "strict signature verification failed" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_POST_VERIFY_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when extracted-app verification fails"

rm -rf "$fixture/output"
expect_failure "unexpected identifier post-archive.invalid" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_POST_METADATA_IDENTIFIER=post-archive.invalid \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when extracted-app metadata changes"

rm -rf "$fixture/output"
codesign_log="$test_tmp/codesign.log"
build_output=$(PATH="$fixture/mock-bin:$PATH" MOCK_CODESIGN_LOG="$codesign_log" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output)
[[ -f "$zip" && -f "$checksum" ]]
(
  cd "$fixture/output"
  shasum -a 256 -c "$(basename "$checksum")" >/dev/null
)
[[ "$(grep -c $'^sign\tcom.youranreus.TokChan\t' "$codesign_log")" -eq 1 ]]
[[ "$(grep -c $'^verify\t' "$codesign_log")" -eq 2 ]]
[[ "$(grep -c $'^display\t' "$codesign_log")" -eq 2 ]]
grep -F $'verify\t' "$codesign_log" | grep -F '/verification/TokChan.app' >/dev/null
fixture_extraction="$test_tmp/fixture-extraction"
mkdir -p "$fixture_extraction"
ditto -x -k "$zip" "$fixture_extraction"
[[ "$(cat "$fixture_extraction/TokChan.app/Contents/_CodeSignature/CodeResources")" == \
  "fixture bundle signature" ]]
[[ "$build_output" == *"ad-hoc signed, not Developer ID signed, and not Apple-notarized"* ]]
[[ "$build_output" == *"intended only for the maintainer's personal use"* ]]
pass "build script signs the complete bundle and preserves its signature through ZIP round trip"
grep -F 'cd "$(dirname "$checksum")"' "$root/.github/workflows/release.yml" >/dev/null
grep -F 'shasum -a 256 -c "$(basename "$checksum")"' \
  "$root/.github/workflows/release.yml" >/dev/null
pass "release workflow verifies the basename checksum from its asset directory"
grep -F 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
  "$root/.github/workflows/release.yml" >/dev/null
! grep -F '/releases/tags/' "$root/.github/workflows/release.yml" >/dev/null
pass "release workflow uses Node 24 checkout and avoids the published-only Tag endpoint"
grep -F 'Test, build, ad-hoc sign, and package universal app' \
  "$root/.github/workflows/release.yml" >/dev/null
grep -F 'ad-hoc signed, not Developer ID signed, and not Apple-notarized' \
  "$root/.github/workflows/release.yml" >/dev/null
! grep -F 'This ZIP is unsigned' "$root/.github/workflows/release.yml" >/dev/null
pass "release workflow describes ad-hoc signing without claiming Developer ID or notarization"

workflow_step="$test_tmp/publish-release-step.sh"
python3 - "$root/.github/workflows/release.yml" "$workflow_step" <<'PY'
from pathlib import Path
import sys

lines = Path(sys.argv[1]).read_text().splitlines()
marker = next(i for i, line in enumerate(lines) if "name: Create or resume draft Release" in line)
start = next(i for i in range(marker, len(lines)) if lines[i].strip() == "run: |") + 1
script = []
for line in lines[start:]:
    if line and not line.startswith("          "):
        break
    script.append(line[10:] if line else "")
Path(sys.argv[2]).write_text("\n".join(script) + "\n")
PY

workflow_mock_bin="$test_tmp/workflow-mock-bin"
workflow_state="$test_tmp/workflow-release-state"
mkdir -p "$workflow_mock_bin"
printf draft > "$workflow_state"
cat > "$workflow_mock_bin/gh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$1" == api && " $* " == *" --paginate "* ]]; then
  if [[ "$(cat "${MOCK_RELEASE_STATE:?}")" != absent && "${MOCK_LIST_INVISIBLE:-}" != 1 ]]; then
    printf '123\ttrue\n'
  fi
elif [[ "$1" == api && " $* " == *" --method POST "* ]]; then
  [[ "$(cat "${MOCK_RELEASE_STATE:?}")" == absent ]]
  printf draft > "${MOCK_RELEASE_STATE:?}"
  printf '123\ttrue\n'
elif [[ "$1" == api && " $* " == *" --method PATCH "* ]]; then
  printf published > "${MOCK_RELEASE_STATE:?}"
elif [[ "$1" == api && " $* " == *" --jq .body "* ]]; then
  if [[ -n "${MOCK_RELEASE_BODY:-}" ]]; then
    printf '%s\n' "$MOCK_RELEASE_BODY"
  else
    echo "This app bundle is ad-hoc signed, not Developer ID signed, and not Apple-notarized. Ad-hoc signing provides bundle integrity but no verified developer identity. It is intended for the maintainer's personal use only. Gatekeeper may block or warn on first launch. Verify the SHA-256 checksum before use. It is not ready for ordinary public distribution."
  fi
elif [[ "$1" == api && " $* " == *" --jq .draft "* ]]; then
  [[ "$(cat "${MOCK_RELEASE_STATE:?}")" == draft ]] && echo true || echo false
elif [[ "$1" == api && " $* " == *" --jq .assets[].name "* ]]; then
  printf '%s\n' "${MOCK_ZIP_NAME:?}" "${MOCK_CHECKSUM_NAME:?}"
elif [[ "$1 $2" == 'release upload' ]]; then
  [[ -f "$4" && -f "$5" ]]
else
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi
MOCK
chmod +x "$workflow_mock_bin/gh"
env PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" ZIP="$zip" CHECKSUM="$checksum" \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" bash "$workflow_step" >/dev/null
[[ "$(cat "$workflow_state")" == published ]]
pass "release workflow resumes and publishes a draft by Release ID"
printf absent > "$workflow_state"
env PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" ZIP="$zip" CHECKSUM="$checksum" \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_LIST_INVISIBLE=1 MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" bash "$workflow_step" >/dev/null
[[ "$(cat "$workflow_state")" == published ]]
pass "release workflow publishes a new draft from the create response ID"
printf draft > "$workflow_state"
expect_failure "missing required warning text: no verified developer identity" env \
  PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" ZIP="$zip" CHECKSUM="$checksum" \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" \
  MOCK_RELEASE_BODY='This app bundle is ad-hoc signed, not Developer ID signed, and not Apple-notarized.' \
  bash "$workflow_step"
[[ "$(cat "$workflow_state")" == draft ]]
pass "release workflow refuses a draft with incomplete distribution warnings"

expect_failure "refusing to overwrite existing asset" env PATH="$fixture/mock-bin:$PATH" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
pass "build script refuses stale final assets"

rm -rf "$fixture/output"
mkdir -p "$fixture/output"
ln -s "$fixture/missing-user-asset" "$zip"
expect_failure "refusing to overwrite existing asset" env PATH="$fixture/mock-bin:$PATH" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
[[ -L "$zip" && "$(readlink "$zip")" == "$fixture/missing-user-asset" ]]
rm -f "$zip"
pass "build script preserves a pre-existing dangling asset symlink"

rm -rf "$fixture/output"
publish_lock="$fixture/output/.${fixture_asset}.publishing"
mkdir -p "$publish_lock"
printf 'owned by another process\n' > "$publish_lock/owner"
expect_failure "another publication may be using this asset name" env \
  PATH="$fixture/mock-bin:$PATH" "$fixture/scripts/build-release.sh" --skip-tests --output output
[[ -d "$publish_lock" ]]
[[ "$(cat "$publish_lock/owner")" == "owned by another process" ]]
rm -rf "$publish_lock"
pass "build script preserves a publication lock it did not acquire"

rm -rf "$fixture/output"
expect_failure "Debug and Release MARKETING_VERSION differ" env \
  PATH="$fixture/mock-bin:$PATH" MOCK_RELEASE_DRIFT=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
[[ ! -e "$fixture/output/$fixture_asset" ]]
pass "build script rejects configuration drift without a final asset"

cat > "$fixture/mock-bin/mv" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
state=${MOCK_MV_STATE:?}
count=0
[[ -f "$state" ]] && count=$(cat "$state")
count=$((count + 1))
printf '%s' "$count" > "$state"
if [[ $count -eq 2 ]]; then
  exit 1
fi
exec /bin/mv "$@"
MOCK
chmod +x "$fixture/mock-bin/mv"
rm -rf "$fixture/output"
expect_failure "diagnostic log retained" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_MV_STATE="$test_tmp/mv-state" "$fixture/scripts/build-release.sh" --skip-tests --output output
[[ ! -e "$fixture/output/$fixture_asset" ]]
[[ ! -e "$fixture/output/$fixture_asset.sha256" ]]
rm "$fixture/mock-bin/mv"
pass "build script removes its ZIP when checksum publication fails"

make_release_repo() {
  local work=$1
  local bare=$2
  mkdir -p "$work/scripts/lib" "$work/TokChan.xcodeproj" "$work/mock-bin"
  cp "$root/scripts/release.sh" "$work/scripts/"
  cp "$root/scripts/lib/project-version.py" "$work/scripts/lib/"
  cp "$root/TokChan.xcodeproj/project.pbxproj" "$work/TokChan.xcodeproj/"
  python3 "$work/scripts/lib/project-version.py" \
    "$work/TokChan.xcodeproj/project.pbxproj" set \
    --marketing "$fixture_version" --build "$fixture_build" >/dev/null
  cat > "$work/scripts/build-release.sh" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
read -r version _ < <(
  python3 scripts/lib/project-version.py TokChan.xcodeproj/project.pbxproj get
)
mkdir -p dist
printf fake > "dist/TokChan-v${version}-macos-universal.zip"
printf checksum > "dist/TokChan-v${version}-macos-universal.zip.sha256"
if [[ "${MOCK_BUILD_MUTATES_TRACKED:-}" == 1 ]]; then
  printf changed > tracked-source
fi
MOCK
  cat > "$work/.gitignore" <<'EOF'
dist/
EOF
  printf stable > "$work/tracked-source"
  chmod +x "$work/scripts/"*.sh "$work/scripts/lib/project-version.py"
  git init --bare "$bare" >/dev/null
  git -C "$work" init -b master >/dev/null
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email release-test@example.com
  git -C "$work" add .
  git -C "$work" commit -m initial >/dev/null
  git -C "$work" remote add origin "$bare"
  git -C "$work" push -u origin master >/dev/null
}

assert_release_type() {
  local release_type=$1
  local expected_version=$2
  local work=$3
  local command_path=$4
  local push_release=${5:-false}
  local expected_tag="v$expected_version"

  if $push_release; then
    printf 'yes\npush\n' | env PATH="$command_path" \
      "$work/scripts/release.sh" "$release_type" --push >/dev/null
  else
    printf 'yes\n' | env PATH="$command_path" \
      "$work/scripts/release.sh" "$release_type" >/dev/null
  fi
  [[ "$(git -C "$work" log -1 --format=%s)" == "chore(release): $expected_tag" ]]
  [[ "$(git -C "$work" diff-tree --no-commit-id --name-only -r HEAD)" == TokChan.xcodeproj/project.pbxproj ]]
  [[ "$(git -C "$work" tag -l "$expected_tag")" == "$expected_tag" ]]
  [[ "$(git -C "$work" cat-file -t "$expected_tag")" == tag ]]
  [[ "$(git -C "$work" for-each-ref --format='%(contents:subject)' "refs/tags/$expected_tag")" == "TokChan $expected_tag" ]]
  [[ "$(git -C "$work" rev-list -n 1 "$expected_tag")" == "$(git -C "$work" rev-parse HEAD)" ]]
  [[ "$(python3 "$work/scripts/lib/project-version.py" "$work/TokChan.xcodeproj/project.pbxproj" get)" == "$expected_version $next_build" ]]

  if $push_release; then
    [[ "$(git --git-dir="${work}.git" rev-parse refs/heads/master)" == "$(git -C "$work" rev-parse HEAD)" ]]
    [[ "$(git --git-dir="${work}.git" rev-list -n 1 "$expected_tag")" == "$(git -C "$work" rev-parse HEAD)" ]]
  fi
}

release_work="$test_tmp/release"
release_bare="$test_tmp/release.git"
make_release_repo "$release_work" "$release_bare"
assert_release_type patch "$patch_version" "$release_work" "$release_work/mock-bin:$PATH"
pass "release script creates a local version commit and annotated patch Tag"

no_gh_path="$test_tmp/no-gh-bin"
mkdir -p "$no_gh_path"
for command_name in bash dirname git mkdir python3; do
  ln -s "$(command -v "$command_name")" "$no_gh_path/$command_name"
done
! PATH="$no_gh_path" command -v gh >/dev/null 2>&1
! grep -Eq '(^|[[:space:]])gh([[:space:]]|$)' "$root/scripts/release.sh"
grep -Eq '(^|[[:space:]])gh api([[:space:]]|$)' "$root/.github/workflows/release.yml"
minor_work="$test_tmp/minor"; minor_bare="$test_tmp/minor.git"
make_release_repo "$minor_work" "$minor_bare"
assert_release_type minor "$minor_version" "$minor_work" "$no_gh_path"
pass "release script creates a minor release without GitHub CLI"

major_work="$test_tmp/major"; major_bare="$test_tmp/major.git"
make_release_repo "$major_work" "$major_bare"
assert_release_type major "$major_version" "$major_work" "$major_work/mock-bin:$PATH" true
pass "release script creates and atomically pushes a major release commit and annotated Tag"

# Fresh fixtures keep each guard independent.
dirty_work="$test_tmp/dirty"; dirty_bare="$test_tmp/dirty.git"
make_release_repo "$dirty_work" "$dirty_bare"
echo dirty > "$dirty_work/untracked"
expect_failure "working tree and index must be clean" env PATH="$dirty_work/mock-bin:$PATH" \
  "$dirty_work/scripts/release.sh" patch
pass "release script rejects a dirty tree"

branch_work="$test_tmp/branch"; branch_bare="$test_tmp/branch.git"
make_release_repo "$branch_work" "$branch_bare"
git -C "$branch_work" checkout -b release-test >/dev/null
expect_failure "releases must be prepared from master" env PATH="$branch_work/mock-bin:$PATH" \
  "$branch_work/scripts/release.sh" patch
pass "release script rejects a non-master branch"

sync_work="$test_tmp/sync"; sync_bare="$test_tmp/sync.git"
make_release_repo "$sync_work" "$sync_bare"
echo local > "$sync_work/local"
git -C "$sync_work" add local
git -C "$sync_work" commit -m local >/dev/null
expect_failure "HEAD must exactly match origin/master" env PATH="$sync_work/mock-bin:$PATH" \
  "$sync_work/scripts/release.sh" patch
pass "release script rejects an unsynchronized branch"

tag_work="$test_tmp/tag"; tag_bare="$test_tmp/tag.git"
make_release_repo "$tag_work" "$tag_bare"
git -C "$tag_work" tag -a "$next_tag" -m duplicate
expect_failure "local Tag already exists" env PATH="$tag_work/mock-bin:$PATH" \
  "$tag_work/scripts/release.sh" patch
pass "release script rejects a duplicate local Tag"

remote_tag_work="$test_tmp/remote-tag"; remote_tag_bare="$test_tmp/remote-tag.git"
make_release_repo "$remote_tag_work" "$remote_tag_bare"
git -C "$remote_tag_work" tag -a "$next_tag" -m duplicate
git -C "$remote_tag_work" push origin "$next_tag" >/dev/null
git -C "$remote_tag_work" tag -d "$next_tag" >/dev/null
expect_failure "local Tag already exists" env PATH="$remote_tag_work/mock-bin:$PATH" \
  "$remote_tag_work/scripts/release.sh" patch
[[ "$(git -C "$remote_tag_work" log -1 --format=%s)" == initial ]]
[[ "$(python3 "$remote_tag_work/scripts/lib/project-version.py" "$remote_tag_work/TokChan.xcodeproj/project.pbxproj" get)" == "$fixture_version $fixture_build" ]]
pass "release script rejects a duplicate remote Tag before version mutation"

mutation_work="$test_tmp/mutation"; mutation_bare="$test_tmp/mutation.git"
make_release_repo "$mutation_work" "$mutation_bare"
expect_failure "unexpected tracked changes appeared" bash -c \
  "printf 'yes\\n' | env PATH='$mutation_work/mock-bin:$PATH' MOCK_BUILD_MUTATES_TRACKED=1 '$mutation_work/scripts/release.sh' patch"
[[ -z "$(git -C "$mutation_work" tag --list "$next_tag")" ]]
[[ "$(git -C "$mutation_work" log -1 --format=%s)" == initial ]]
pass "release script rejects source changes that appear after testing"

python3 "$root/tests/test_project_version.py"
pass "structured project-version tests pass"

echo "1..$pass_count"

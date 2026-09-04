#!/usr/bin/env bash
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_tmp=$(mktemp -d "${TMPDIR:-/tmp}/tokchan-script-tests.XXXXXX")
trap 'rm -rf -- "$test_tmp"' EXIT

fixture_version=7.8.9
fixture_build=42
next_version=7.8.10
next_build=43
fixture_asset="TokChan-v${fixture_version}-macos-universal.zip"
next_tag="v${next_version}"
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

expect_failure "unknown argument" "$root/scripts/build-release.sh" --unknown
pass "build script rejects unknown arguments"
expect_failure "only be specified once" "$root/scripts/build-release.sh" --skip-tests --skip-tests
pass "build script rejects duplicate arguments"

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
PATH="$fixture/mock-bin:$PATH" "$fixture/scripts/build-release.sh" --skip-tests --output output >/dev/null
zip="$fixture/output/$fixture_asset"
checksum="$zip.sha256"
[[ -f "$zip" && -f "$checksum" ]]
(
  cd "$fixture/output"
  shasum -a 256 -c "$(basename "$checksum")" >/dev/null
)
pass "build script produces the canonical ZIP/checksum pair"
grep -F 'cd "$(dirname "$checksum")"' "$root/.github/workflows/release.yml" >/dev/null
grep -F 'shasum -a 256 -c "$(basename "$checksum")"' \
  "$root/.github/workflows/release.yml" >/dev/null
pass "release workflow verifies the basename checksum from its asset directory"

expect_failure "refusing to overwrite existing asset" env PATH="$fixture/mock-bin:$PATH" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
pass "build script refuses stale final assets"

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
  cat > "$work/mock-bin/gh" <<'MOCK'
#!/usr/bin/env bash
case "$1 $2" in
  'auth status'|'repo view') exit 0 ;;
  'api repos/'*)
    if [[ "${MOCK_GH_API_ERROR:-}" == 1 ]]; then
      echo 'gh: API rate limit exceeded (HTTP 403)' >&2
      exit 1
    fi
    echo 'gh: Not Found (HTTP 404)' >&2
    exit 1
    ;;
  *) echo "unexpected gh invocation: $*" >&2; exit 1 ;;
esac
MOCK
  chmod +x "$work/scripts/"*.sh "$work/scripts/lib/project-version.py" "$work/mock-bin/gh"
  git init --bare "$bare" >/dev/null
  git -C "$work" init -b master >/dev/null
  git -C "$work" config user.name 'Release Test'
  git -C "$work" config user.email release-test@example.com
  git -C "$work" add .
  git -C "$work" commit -m initial >/dev/null
  git -C "$work" remote add origin "$bare"
  git -C "$work" push -u origin master >/dev/null
}

release_work="$test_tmp/release"
release_bare="$test_tmp/release.git"
make_release_repo "$release_work" "$release_bare"
printf 'yes\n' | env PATH="$release_work/mock-bin:$PATH" "$release_work/scripts/release.sh" patch >/dev/null
[[ "$(git -C "$release_work" log -1 --format=%s)" == "chore(release): $next_tag" ]]
[[ "$(git -C "$release_work" tag -l "$next_tag")" == "$next_tag" ]]
[[ "$(git -C "$release_work" cat-file -t "$next_tag")" == tag ]]
[[ "$(python3 "$release_work/scripts/lib/project-version.py" "$release_work/TokChan.xcodeproj/project.pbxproj" get)" == "$next_version $next_build" ]]
pass "release script creates a local version commit and annotated patch Tag"

# Fresh fixtures keep each guard independent.
dirty_work="$test_tmp/dirty"; dirty_bare="$test_tmp/dirty.git"
make_release_repo "$dirty_work" "$dirty_bare"
echo dirty > "$dirty_work/untracked"
expect_failure "working tree and index must be clean" env PATH="$dirty_work/mock-bin:$PATH" \
  "$dirty_work/scripts/release.sh" patch
pass "release script rejects a dirty tree"

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

mutation_work="$test_tmp/mutation"; mutation_bare="$test_tmp/mutation.git"
make_release_repo "$mutation_work" "$mutation_bare"
expect_failure "unexpected tracked changes appeared" bash -c \
  "printf 'yes\\n' | env PATH='$mutation_work/mock-bin:$PATH' MOCK_BUILD_MUTATES_TRACKED=1 '$mutation_work/scripts/release.sh' patch"
[[ -z "$(git -C "$mutation_work" tag --list "$next_tag")" ]]
[[ "$(git -C "$mutation_work" log -1 --format=%s)" == initial ]]
pass "release script rejects source changes that appear after testing"

api_work="$test_tmp/api"; api_bare="$test_tmp/api.git"
make_release_repo "$api_work" "$api_bare"
expect_failure "could not confirm that GitHub Release" env \
  PATH="$api_work/mock-bin:$PATH" MOCK_GH_API_ERROR=1 \
  "$api_work/scripts/release.sh" patch
pass "release script fails closed on GitHub API errors"

python3 "$root/tests/test_project_version.py"
pass "structured project-version tests pass"

echo "1..$pass_count"

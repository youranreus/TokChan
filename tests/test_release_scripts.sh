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
fixture_asset="TokChan-v${fixture_version}-macos-universal.dmg"
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
set -euo pipefail
[[ -z "${MOCK_TRUST_LOG:-}" ]] || echo "$*" >> "$MOCK_TRUST_LOG"
if [[ "$1 $2" == 'notarytool submit' ]]; then
  kind=app
  [[ "$3" == *.dmg ]] && kind=dmg
  status=Accepted
  [[ "${MOCK_NOTARY_FAILURE:-}" != "$kind" ]] || status=Invalid
  [[ "${MOCK_NOTARY_PENDING:-}" != "$kind" ]] || status='In Progress'
  printf '{"id":"12345678-1234-1234-1234-123456789abc","status":"%s"}\n' "$status"
  [[ "${MOCK_NOTARY_EXIT_FAILURE:-}" != "$kind" ]] || exit 1
elif [[ "$1 $2" == 'stapler staple' || "$1 $2" == 'stapler validate' ]]; then
  [[ "${MOCK_STAPLER_FAILURE:-}" != "$2" ]] || exit 1
  if [[ "$2" == staple ]]; then
    if [[ "$3" == *.app ]]; then
      echo ticket > "$3/Contents/stapled-ticket-fixture"
    else
      echo ticket >> "$3"
    fi
  elif [[ "$3" == *.app ]]; then
    [[ -f "$3/Contents/stapled-ticket-fixture" ]]
  else
    [[ "$(tail -1 "$3")" == ticket ]]
  fi
fi
MOCK
  cat > "$fixture/mock-bin/spctl" <<'MOCK'
#!/usr/bin/env bash
[[ -z "${MOCK_TRUST_LOG:-}" ]] || echo "spctl $*" >> "$MOCK_TRUST_LOG"
[[ "${MOCK_GATEKEEPER_FAILURE:-}" != 1 ]]
MOCK
  cat > "$fixture/mock-bin/lipo" <<'MOCK'
#!/usr/bin/env bash
if [[ "$*" == *verification-mount* && "${MOCK_DMG_BAD_ARCHITECTURES:-}" == 1 ]]; then
  echo arm64
else
  echo 'arm64 x86_64'
fi
MOCK
  cat > "$fixture/mock-bin/shasum" <<'MOCK'
#!/usr/bin/env bash
if [[ "${MOCK_CHECKSUM_FAILURE:-}" == 1 && "$*" == *macos-universal.dmg ]]; then
  exit 1
fi
exec /usr/bin/shasum "$@"
MOCK
  cat > "$fixture/mock-bin/osascript" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == - && -d "$2/TokChan.app" ]]
[[ -L "$2/Applications" && "$(readlink "$2/Applications")" == /Applications ]]
[[ -z "${MOCK_OSASCRIPT_LOG:-}" ]] || printf '%s\n' "$*" >> "$MOCK_OSASCRIPT_LOG"
[[ "${MOCK_LAYOUT_FAILURE:-}" != 1 ]] || exit 1
layout_script=$(cat)
if [[ "${MOCK_REQUIRE_EXPLICIT_LAYOUT_WINDOW:-}" == 1 ]]; then
  grep -F 'set targetWindow to make new Finder window' <<< "$layout_script" >/dev/null
  grep -F 'set target of targetWindow to targetFolder' <<< "$layout_script" >/dev/null
  ! grep -F 'container window of targetFolder' <<< "$layout_script" >/dev/null
fi
[[ "${MOCK_LAYOUT_MISSING:-}" == 1 ]] || printf fixture > "$2/.DS_Store"
MOCK
  cat > "$fixture/mock-bin/hdiutil" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
command_name=$1
shift
[[ -z "${MOCK_HDIUTIL_LOG:-}" ]] || printf '%s\t%s\n' "$command_name" "$*" >> "$MOCK_HDIUTIL_LOG"

argument_after() {
  local wanted=$1
  shift
  while (($#)); do
    if [[ "$1" == "$wanted" ]]; then
      printf '%s\n' "$2"
      return
    fi
    shift
  done
  return 1
}

case "$command_name" in
  create)
    [[ "${MOCK_DMG_CREATE_FAILURE:-}" != 1 ]] || exit 1
    source=$(argument_after -srcfolder "$@")
    output=${!#}
    [[ -d "$source/TokChan.app" ]]
    [[ -L "$source/Applications" && "$(readlink "$source/Applications")" == /Applications ]]
    printf 'writable image fixture\n' > "$output"
    ;;
  attach)
    mount_point=$(argument_after -mountpoint "$@")
    image=${!#}
    if [[ "$image" == */TokChan-writable.dmg ]]; then
      phase=layout
      device=/dev/disk91
      work_dir=$(dirname "$image")
    else
      phase=verification
      device=/dev/disk92
      work_dir=$(dirname "$(dirname "$image")")
    fi
    [[ "${MOCK_DMG_ATTACH_FAILURE:-}" != "$phase" ]] || exit 1
    /usr/bin/ditto "$work_dir/dmg-root/" "$mount_point/"
    if [[ "$phase" == verification ]]; then
      if [[ "${MOCK_DMG_BAD_SYMLINK:-}" == 1 ]]; then
        rm "$mount_point/Applications"
        ln -s /tmp "$mount_point/Applications"
      fi
      [[ "${MOCK_DMG_EXTRA_ENTRY:-}" != 1 ]] || printf extra > "$mount_point/ReadMe.txt"
      [[ "${MOCK_DMG_MISSING_APP:-}" != 1 ]] || rm -rf "$mount_point/TokChan.app"
      if [[ "${MOCK_DMG_BAD_VERSION:-}" == 1 ]]; then
        /usr/libexec/PlistBuddy -c 'Set :CFBundleShortVersionString 0.0.0' \
          "$mount_point/TokChan.app/Contents/Info.plist"
      fi
    fi
    if [[ "${MOCK_DMG_BAD_PLIST:-}" == "$phase" ]]; then
      printf '%s\n' '<?xml version="1.0"?><plist version="1.0"><dict/></plist>'
    else
      python3 - "$device" "$mount_point" <<'PY'
import plistlib
import sys
plistlib.dump({"system-entities": [{"dev-entry": sys.argv[1], "mount-point": sys.argv[2]}]}, sys.stdout.buffer)
PY
    fi
    ;;
  detach)
    phase=layout
    [[ "$1" == /dev/disk92 ]] && phase=verification
    [[ "${MOCK_DMG_DETACH_FAILURE:-}" != "$phase" ]] || exit 1
    ;;
  convert)
    [[ "${MOCK_DMG_CONVERT_FAILURE:-}" != 1 ]] || exit 1
    output=$(argument_after -o "$@")
    printf 'compressed image fixture\n' > "$output"
    ;;
  verify)
    [[ "${MOCK_DMG_VERIFY_FAILURE:-}" != 1 ]] || exit 1
    [[ -f "$1" ]]
    ;;
  *)
    echo "unexpected hdiutil invocation: $command_name $*" >&2
    exit 64
    ;;
esac
MOCK
  cat > "$fixture/mock-bin/codesign" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail

record() {
  [[ -z "${MOCK_CODESIGN_LOG:-}" ]] || printf '%s\n' "$1" >> "$MOCK_CODESIGN_LOG"
}

identifier_for() {
  case "$1" in
    */Versions/B/Autoupdate) echo Autoupdate-555549442a006fc962db330cbcadfaa40625e4c6 ;;
    */Versions/B/Updater.app) echo org.sparkle-project.Sparkle.Updater ;;
    */Versions/B/XPCServices/Downloader.xpc) echo org.sparkle-project.DownloaderService ;;
    */Versions/B/XPCServices/Installer.xpc) echo org.sparkle-project.InstallerLauncher ;;
    *.framework) echo org.sparkle-project.Sparkle ;;
    *) echo com.youranreus.TokChan ;;
  esac
}

if [[ "$1" == -d && "$2" == --entitlements && "$3" == :- ]]; then
  cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict><key>com.apple.application-identifier</key><string>org.sparkle-project.Sparkle.Autoupdate</string></dict></plist>
PLIST
  exit 0
fi

artifact=${!#}
[[ -z "${MOCK_TRUST_LOG:-}" ]] || echo "codesign $*" >> "$MOCK_TRUST_LOG"
if [[ "$1" == --force ]]; then
  [[ " $* " != *" --deep "* ]]
  [[ " $* " == *" --options runtime "* || "$artifact" == *.dmg ]]
  if [[ "${MOCK_FORMAL:-}" == 1 ]]; then
    [[ " $* " == *" --timestamp "* && " $* " == *" --keychain "* ]]
    [[ "${MOCK_FORMAL_SIGN_FAILURE:-}" != 1 ]] || exit 1
  else
    [[ " $* " == *" --sign - "* ]]
    [[ "${MOCK_CODESIGN_SIGN_FAILURE:-}" != 1 ]] || exit 1
  fi
  record "$(printf 'sign-code\t%s' "$artifact")"
  if [[ "$artifact" == */TokChan.app ]]; then
    mkdir -p "$artifact/Contents/_CodeSignature"
    printf signed > "$artifact/Contents/_CodeSignature/CodeResources"
  fi
  exit 0
fi

if [[ "$1" == --verify ]]; then
  record "$(printf 'verify\t%s' "$artifact")"
  if [[ "$artifact" == */TokChan.app ]]; then
    [[ -f "$artifact/Contents/_CodeSignature/CodeResources" ]] || exit 1
    if [[ "$artifact" == */verification-mount/TokChan.app ]]; then
      [[ "${MOCK_CODESIGN_POST_VERIFY_FAILURE:-}" != 1 ]] || exit 1
    else
      [[ "${MOCK_CODESIGN_PRE_VERIFY_FAILURE:-}" != 1 ]] || exit 1
    fi
  fi
  if [[ "${MOCK_FORMAL:-}" == 1 ]]; then
    [[ "${MOCK_FORMAL_VERIFY_FAILURE:-}" != 1 ]] || exit 1
  fi
  exit 0
fi

if [[ "$1" == -dr && "$2" == - ]]; then
  echo "Executable=$artifact" >&2
  if [[ "${MOCK_NO_DESIGNATED_REQUIREMENT:-}" != 1 ]]; then
    if [[ "${MOCK_FORMAL:-}" == 1 || "${MOCK_DESIGNATED_REQUIREMENT_STYLE:-}" == formal ]]; then
      requirement="designated => identifier \"$(identifier_for "$artifact")\" and anchor apple generic"
    else
      requirement='# designated => cdhash H"fixture"'
    fi
    echo "$requirement" >&2
    [[ "${MOCK_DUPLICATE_DESIGNATED_REQUIREMENT:-}" != 1 ]] || echo "$requirement" >&2
    [[ "${MOCK_MALFORMED_DESIGNATED_REQUIREMENT:-}" != 1 ]] || echo 'designated =>' >&2
  fi
  exit 0
fi

if [[ "$1" == -dv && "$2" == --verbose=4 ]]; then
  record "$(printf 'display\t%s' "$artifact")"
  [[ "${MOCK_CODESIGN_METADATA_FAILURE:-}" != 1 ]] || exit 1
  identifier=$(identifier_for "$artifact")
  if [[ "$artifact" == */TokChan.app ]]; then
    identifier=${MOCK_CODESIGN_METADATA_IDENTIFIER:-$identifier}
    if [[ "$artifact" == */verification-mount/TokChan.app ]]; then
      [[ "${MOCK_CODESIGN_POST_METADATA_FAILURE:-}" != 1 ]] || exit 1
      identifier=${MOCK_CODESIGN_POST_METADATA_IDENTIFIER:-$identifier}
    fi
  fi
  echo "Identifier=$identifier" >&2
  if [[ "${MOCK_FORMAL:-}" == 1 ]]; then
    echo "Authority=${MOCK_AUTHORITY:-$APPLE_SIGNING_IDENTITY}" >&2
    echo "TeamIdentifier=${MOCK_TEAM:-$APPLE_TEAM_ID}" >&2
    [[ "${MOCK_NO_TIMESTAMP:-}" == 1 ]] || echo 'Timestamp=Sep 8, 2026 at 10:00:00 AM' >&2
  else
    echo 'Signature=adhoc' >&2
    echo 'TeamIdentifier=not set' >&2
  fi
  [[ "${MOCK_NO_RUNTIME:-}" == 1 ]] || echo 'CodeDirectory v=20500 size=123 flags=0x10000(runtime)' >&2
  echo 'Info.plist entries=3' >&2
  echo 'Sealed Resources version=2 rules=13 files=2' >&2
  if [[ "${MOCK_CODESIGN_DUPLICATE_IDENTIFIER:-}" == 1 && "$artifact" == */TokChan.app ]]; then
    echo "Identifier=$identifier" >&2
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
  sparkle="$app/Contents/Frameworks/Sparkle.framework/Versions/B"
  mkdir -p "$app/Contents/MacOS" "$sparkle/Updater.app/Contents/MacOS" \
    "$sparkle/XPCServices/Downloader.xpc/Contents/MacOS" \
    "$sparkle/XPCServices/Installer.xpc/Contents/MacOS"
  printf 'fake executable' > "$app/Contents/MacOS/TokChan"
  printf 'autoupdate' > "$sparkle/Autoupdate"
  printf 'updater' > "$sparkle/Updater.app/Contents/MacOS/Updater"
  printf 'downloader' > "$sparkle/XPCServices/Downloader.xpc/Contents/MacOS/Downloader"
  printf 'installer' > "$sparkle/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  chmod +x "$app/Contents/MacOS/TokChan" "$sparkle/Autoupdate" \
    "$sparkle/Updater.app/Contents/MacOS/Updater" \
    "$sparkle/XPCServices/Downloader.xpc/Contents/MacOS/Downloader" \
    "$sparkle/XPCServices/Installer.xpc/Contents/MacOS/Installer"
  [[ "${MOCK_SPARKLE_MISSING:-}" != 1 ]] || rm -rf "$sparkle/XPCServices/Installer.xpc"
  [[ "${MOCK_SPARKLE_EXTRA:-}" != 1 ]] || mkdir -p "$sparkle/XPCServices/Unexpected.xpc"
  cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleShortVersionString</key><string>${TEST_FIXTURE_VERSION:?}</string>
<key>CFBundleVersion</key><string>${TEST_FIXTURE_BUILD:?}</string>
<key>CFBundleIdentifier</key><string>com.youranreus.TokChan</string>
<key>SUFeedURL</key><string>https://youranreus.github.io/TokChan/appcast.xml</string>
<key>SUEnableAutomaticChecks</key><false/>
<key>SUPublicEDKey</key><string>${SPARKLE_PUBLIC_ED_KEY:-}</string>
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
dmg="$fixture/output/$fixture_asset"
checksum="$dmg.sha256"
zip="$fixture/output/TokChan-v${fixture_version}-macos-universal.zip"

assert_no_build_assets() {
  [[ ! -e "$dmg" && ! -L "$dmg" && ! -e "$checksum" && ! -L "$checksum" && \
     ! -e "$zip" && ! -L "$zip" ]]
}

expect_failure "ad-hoc signing failed for Sparkle" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_SIGN_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when ad-hoc bundle signing fails"
expect_failure "missing Sparkle signable code" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_SPARKLE_MISSING=1 "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects a missing reviewed Sparkle nested component"
expect_failure "unexpected Sparkle nested bundle inventory" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_SPARKLE_EXTRA=1 "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects an unexpected Sparkle nested component"

rm -rf "$fixture/output"
PATH="$fixture/mock-bin:$PATH" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output >/dev/null
[[ -f "$dmg" && -f "$checksum" && -f "$zip" ]]
pass "build script accepts native ad-hoc codesign designated requirement output"

rm -rf "$fixture/output"
PATH="$fixture/mock-bin:$PATH" MOCK_DESIGNATED_REQUIREMENT_STYLE=formal \
  "$fixture/scripts/build-release.sh" --skip-tests --output output >/dev/null
[[ -f "$dmg" && -f "$checksum" && -f "$zip" ]]
pass "build script accepts native Developer ID codesign designated requirement output"

rm -rf "$fixture/output"
expect_failure "designated requirement is missing" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_NO_DESIGNATED_REQUIREMENT=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when a designated requirement is absent"

rm -rf "$fixture/output"
expect_failure "designated requirement is missing or ambiguous" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DUPLICATE_DESIGNATED_REQUIREMENT=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when designated requirements are ambiguous"

rm -rf "$fixture/output"
expect_failure "designated requirement is missing or ambiguous" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_MALFORMED_DESIGNATED_REQUIREMENT=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when designated requirement output is malformed"

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
post_verify_failure_log="$test_tmp/post-verify-failure-hdiutil.log"
expect_failure "strict signature verification failed" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_POST_VERIFY_FAILURE=1 MOCK_HDIUTIL_LOG="$post_verify_failure_log" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
grep -F $'detach\t/dev/disk92' "$post_verify_failure_log" >/dev/null
pass "build script detaches its verification image when mounted-app verification fails"

rm -rf "$fixture/output"
expect_failure "unexpected identifier post-archive.invalid" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CODESIGN_POST_METADATA_IDENTIFIER=post-archive.invalid \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when mounted-app signature metadata changes"

rm -rf "$fixture/output"
expect_failure "could not create writable disk image" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_CREATE_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when writable DMG creation fails"

rm -rf "$fixture/output"
layout_failure_log="$test_tmp/layout-failure-hdiutil.log"
expect_failure "could not configure Finder disk image layout" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_LAYOUT_FAILURE=1 MOCK_HDIUTIL_LOG="$layout_failure_log" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
grep -F $'detach\t/dev/disk91' "$layout_failure_log" >/dev/null
pass "build script detaches its writable image when Finder layout fails"

rm -rf "$fixture/output"
expect_failure "Finder did not persist disk image layout metadata" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_LAYOUT_MISSING=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when Finder layout metadata is missing"

rm -rf "$fixture/output"
expect_failure "could not attach disk image for readwrite access" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_ATTACH_FAILURE=layout \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when writable DMG attach fails"

rm -rf "$fixture/output"
bad_plist_log="$test_tmp/bad-plist-hdiutil.log"
expect_failure "could not identify owned readwrite disk image attachment" env \
  PATH="$fixture/mock-bin:$PATH" MOCK_DMG_BAD_PLIST=layout MOCK_HDIUTIL_LOG="$bad_plist_log" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
grep -F $'detach\t' "$bad_plist_log" | grep -F '/layout-mount' >/dev/null
pass "build script tracks its owned writable mount when attach plist parsing fails"

rm -rf "$fixture/output"
bad_verification_plist_log="$test_tmp/bad-verification-plist-hdiutil.log"
expect_failure "could not identify owned readonly disk image attachment" env \
  PATH="$fixture/mock-bin:$PATH" MOCK_DMG_BAD_PLIST=verification \
  MOCK_HDIUTIL_LOG="$bad_verification_plist_log" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
grep -F $'detach\t' "$bad_verification_plist_log" | grep -F '/verification-mount' >/dev/null
pass "build script tracks its owned verification mount when attach plist parsing fails"

rm -rf "$fixture/output"
expect_failure "could not detach writable disk image" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_DETACH_FAILURE=layout \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed and retains diagnostics when writable detach fails"

rm -rf "$fixture/output"
expect_failure "could not create compressed disk image" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_CONVERT_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when DMG conversion fails"

rm -rf "$fixture/output"
expect_failure "disk image verification failed" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_VERIFY_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when hdiutil verification fails"

rm -rf "$fixture/output"
expect_failure "could not attach disk image for readonly access" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_ATTACH_FAILURE=verification \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when verification mount fails"

rm -rf "$fixture/output"
expect_failure "does not point to /Applications" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_BAD_SYMLINK=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects a DMG with the wrong Applications symlink"

rm -rf "$fixture/output"
expect_failure "unexpected user-visible disk image entries" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_EXTRA_ENTRY=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects unexpected visible DMG contents"

rm -rf "$fixture/output"
expect_failure "expected app was not found in disk image" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_MISSING_APP=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects a DMG without TokChan.app"

rm -rf "$fixture/output"
expect_failure "version 0.0.0 does not match" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_BAD_VERSION=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects changed mounted-App version metadata"

rm -rf "$fixture/output"
expect_failure "does not contain x86_64" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_BAD_ARCHITECTURES=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script rejects changed mounted-App architectures"

rm -rf "$fixture/output"
expect_failure "could not detach verification disk image" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_DMG_DETACH_FAILURE=verification \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when verification detach fails"

rm -rf "$fixture/output"
expect_failure "diagnostic log retained" env PATH="$fixture/mock-bin:$PATH" \
  MOCK_CHECKSUM_FAILURE=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
assert_no_build_assets
pass "build script fails closed when DMG checksum creation fails"

rm -rf "$fixture/output"
# Public trust failures must never expose final-named assets.
keychain="$test_tmp/signing.keychain-db"
touch "$keychain"
formal_env=(env PATH="$fixture/mock-bin:$PATH" MOCK_FORMAL=1
  APPLE_SIGNING_IDENTITY='Developer ID Application: Fixture (ABCDEFGHIJ)'
  APPLE_TEAM_ID=ABCDEFGHIJ APPLE_KEYCHAIN_PATH="$keychain" APPLE_NOTARY_PROFILE=fixture
  SPARKLE_PUBLIC_ED_KEY=fixture-public-key)
expect_failure "--notarize requires APPLE_SIGNING_IDENTITY" env -u APPLE_SIGNING_IDENTITY \
  PATH="$fixture/mock-bin:$PATH" "$fixture/scripts/build-release.sh" --notarize --skip-tests --output output
assert_no_build_assets
pass "notarized build requires explicit credentials"
for failure in MOCK_FORMAL_SIGN_FAILURE=1 MOCK_FORMAL_VERIFY_FAILURE=1 MOCK_TEAM=WRONGTEAM0 \
  MOCK_AUTHORITY=wrong MOCK_NO_TIMESTAMP=1 MOCK_NO_RUNTIME=1 MOCK_NOTARY_FAILURE=app \
  MOCK_NOTARY_FAILURE=dmg MOCK_NOTARY_PENDING=app MOCK_NOTARY_EXIT_FAILURE=app \
  MOCK_STAPLER_FAILURE=staple MOCK_STAPLER_FAILURE=validate MOCK_GATEKEEPER_FAILURE=1; do
  expect_failure "build-release:" "${formal_env[@]}" "$failure" \
    "$fixture/scripts/build-release.sh" --notarize --skip-tests --output output
  assert_no_build_assets
  pass "notarized build fails closed: $failure"
done
expect_failure '"status":"Invalid"' "${formal_env[@]}" GITHUB_ACTIONS=true MOCK_NOTARY_FAILURE=app \
  "$fixture/scripts/build-release.sh" --notarize --skip-tests --output output
assert_no_build_assets
pass "failed CI notarization preserves Apple response in job output"
trust_log="$test_tmp/trust.log"
"${formal_env[@]}" MOCK_TRUST_LOG="$trust_log" \
  "$fixture/scripts/build-release.sh" --notarize --skip-tests --output output >/dev/null
[[ -f "$dmg" && -f "$checksum" && -f "$zip" ]]
[[ "$(unzip -Z1 "$zip" | head -n 1)" == TokChan.app/* ]]
[[ "$(grep -c '^notarytool submit ' "$trust_log")" -eq 2 ]]
[[ "$(grep -c '^stapler staple ' "$trust_log")" -eq 2 ]]
[[ "$(grep -c '^stapler validate ' "$trust_log")" -eq 4 ]]
grep -F 'spctl --assess --type execute --verbose=4 ' "$trust_log" | grep -F '/verification-mount/TokChan.app' >/dev/null
python3 - "$trust_log" <<'PYTEST'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
operations = [line.split()[:2] for line in lines]
assert operations.index(['stapler', 'staple']) > operations.index(['notarytool', 'submit'])
app_validate = next(i for i, line in enumerate(lines) if line.startswith('stapler validate ') and line.endswith('TokChan.app'))
dmg_sign = next(i for i, line in enumerate(lines) if line.startswith('codesign --force') and line.endswith('.dmg'))
spctl = next(i for i, line in enumerate(lines) if line.startswith('spctl '))
zip_validate = max(i for i, line in enumerate(lines) if line.startswith('stapler validate ') and line.endswith('TokChan.app'))
assert dmg_sign > app_validate
assert zip_validate > spctl
PYTEST
(cd "$fixture/output" && shasum -a 256 -c "$(basename "$checksum")" >/dev/null)
pass "notarized app and DMG pass signing, ticket, mounted Gatekeeper and checksum gates"
rm -rf "$fixture/output"
codesign_log="$test_tmp/codesign.log"
hdiutil_log="$test_tmp/hdiutil.log"
osascript_log="$test_tmp/osascript.log"
build_output=$(PATH="$fixture/mock-bin:$PATH" MOCK_CODESIGN_LOG="$codesign_log" \
  MOCK_HDIUTIL_LOG="$hdiutil_log" MOCK_OSASCRIPT_LOG="$osascript_log" \
  MOCK_REQUIRE_EXPLICIT_LAYOUT_WINDOW=1 \
  "$fixture/scripts/build-release.sh" --skip-tests --output output)
[[ -f "$dmg" && -f "$checksum" && -f "$zip" ]]
[[ "$(unzip -Z1 "$zip" | head -n 1)" == TokChan.app/* ]]
(
  cd "$fixture/output"
  shasum -a 256 -c "$(basename "$checksum")" >/dev/null
)
[[ "$(grep -c $'^sign-code\t' "$codesign_log")" -eq 6 ]]
[[ "$(grep -c $'^verify\t' "$codesign_log")" -eq 8 ]]
[[ "$(grep -c $'^display\t' "$codesign_log")" -eq 8 ]]
python3 - "$codesign_log" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
def signed(suffix):
    return next(i for i, line in enumerate(lines) if line.startswith("sign-code\t") and line.endswith(suffix))
leaves = [
    signed("Versions/B/Autoupdate"),
    signed("Versions/B/Updater.app"),
    signed("Versions/B/XPCServices/Downloader.xpc"),
    signed("Versions/B/XPCServices/Installer.xpc"),
]
framework = signed("Sparkle.framework")
app = signed("TokChan.app")
assert all(index < framework for index in leaves)
assert framework < app
PY
grep -F $'verify\t' "$codesign_log" | grep -F '/verification-mount/TokChan.app' >/dev/null
[[ "$(grep -c $'^attach\t' "$hdiutil_log")" -eq 2 ]]
[[ "$(grep -c $'^detach\t' "$hdiutil_log")" -eq 2 ]]
grep -F $'create\t-quiet -fs HFS+ -format UDRW -volname TokChan -srcfolder ' "$hdiutil_log" >/dev/null
grep -F $'convert\t' "$hdiutil_log" | grep -F -- '-format UDZO' >/dev/null
grep -F $'verify\t' "$hdiutil_log" >/dev/null
grep -F -- '-readonly -nobrowse -noautoopen -mountpoint' "$hdiutil_log" >/dev/null
[[ -s "$osascript_log" ]]
[[ "$build_output" == *"ad-hoc signed, not Developer ID signed, and not Apple-notarized"* ]]
[[ "$build_output" == *"intended only for the maintainer's personal use"* ]]
pass "build script creates, lays out, mounts, and reverifies the signed DMG"
grep -F 'cd "$(dirname "$checksum")"' "$root/.github/workflows/release.yml" >/dev/null
grep -F 'shasum -a 256 -c "$(basename "$checksum")"' \
  "$root/.github/workflows/release.yml" >/dev/null
pass "release workflow verifies the basename checksum from its asset directory"
grep -F 'actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1' \
  "$root/.github/workflows/release.yml" >/dev/null
! grep -F '/releases/tags/' "$root/.github/workflows/release.yml" >/dev/null
pass "release workflow uses Node 24 checkout and avoids the published-only Tag endpoint"
python3 "$root/tests/test_workflow_action_pins.py" >/dev/null
pass "release workflow uses the reviewed offline action-pin allowlist"
grep -F 'scripts/ci-build-release.sh' \
  "$root/.github/workflows/release.yml" >/dev/null
grep -F 'This app is Developer ID signed and Apple-notarized.' \
  "$root/.github/workflows/release.yml" >/dev/null
! grep -F 'This ZIP is unsigned' "$root/.github/workflows/release.yml" >/dev/null
grep -F 'set position of item "TokChan.app" of targetFolder to {140, 160}' \
  "$root/scripts/build-release.sh" >/dev/null
grep -F 'set position of item "Applications" of targetFolder to {410, 160}' \
  "$root/scripts/build-release.sh" >/dev/null
! grep -Ei 'background (picture|image)' "$root/scripts/build-release.sh" >/dev/null
grep -F 'TokChan-v${version}-macos-universal.dmg' \
  "$root/.github/workflows/release.yml" >/dev/null
grep -F 'macos-universal.zip' "$root/.github/workflows/release.yml" >/dev/null
workflow=$(cat "$root/.github/workflows/release.yml")
[[ "${workflow%%      - name: Create or resume draft Release*}" == *"name: Generate signed Sparkle appcast"* ]]
[[ "$workflow" == *"name: Deploy appcast last"* ]]
python3 - "$root/.github/workflows/release.yml" <<'PY'
from pathlib import Path
import subprocess
import sys
import tempfile

lines = Path(sys.argv[1]).read_text().splitlines()
blocks = []
for index, line in enumerate(lines):
    if line.strip() != "run: |":
        continue
    indent = len(line) - len(line.lstrip()) + 2
    block = []
    for candidate in lines[index + 1:]:
        candidate_indent = len(candidate) - len(candidate.lstrip())
        if candidate.strip() and candidate_indent < indent:
            break
        block.append(candidate[indent:] if len(candidate) >= indent else "")
    blocks.append("\n".join(block) + "\n")
if not blocks:
    raise SystemExit("no workflow shell blocks found")
with tempfile.TemporaryDirectory() as directory:
    for index, block in enumerate(blocks):
        path = Path(directory) / f"run-{index}.sh"
        path.write_text(block)
        subprocess.run(["bash", "-n", str(path)], check=True)
PY
python3 - "$root/.github/workflows/release.yml" <<'PY'
import re, sys
from pathlib import Path
text = Path(sys.argv[1]).read_text()
permissions = re.search(r"(?m)^permissions:\n((?:  [^\n]+\n)+)", text)
assert permissions
assert set(re.findall(r"^  ([a-z-]+): (\w+)$", permissions.group(1), re.M)) == {
    ("contents", "write"), ("pages", "write"), ("id-token", "write")
}
assert "name: github-pages" in text and "steps.deployment.outputs.page_url" in text
assert "name: Inspect immutable Release recovery state" in text
assert "if: steps.recovery.outputs.enabled != 'true'" in text
for action, revision in re.findall(r"uses: ([^@\s]+)@([^\s]+)", text):
    assert re.fullmatch(r"[0-9a-f]{40}", revision), (action, revision)
for required in ["SPARKLE_PRIVATE_KEY_BASE64", "vars.SPARKLE_PUBLIC_ED_KEY", "github.token"]:
    assert required in text
assert text.index("Inspect immutable Release recovery state") < text.index("Generate signed Sparkle appcast")
assert "APPLE_SIGNING_IDENTITY: ${{ secrets.APPLE_SIGNING_IDENTITY }}" in text
assert "signature_metadata=$(codesign -dv --verbose=4 \"$app\" 2>&1)" in text
assert "candidate appcast changed or dropped prior feed history" in text
assert "curl --fail --silent --show-error --location --retry 5 --retry-all-errors" in text
assert text.index("Generate signed Sparkle appcast") < text.index("Create or resume draft Release")
assert text.index("Verify published update archive") < text.index("Upload appcast Pages artifact") < text.index("Deploy appcast last")
PY
pass "release workflow permissions, pins, environment, credentials, and publication order are exact"

appcast_step="$test_tmp/generate-appcast-step.sh"
python3 - "$root/.github/workflows/release.yml" "$appcast_step" <<'PY'
from pathlib import Path
import sys
lines = Path(sys.argv[1]).read_text().splitlines()
marker = next(i for i, line in enumerate(lines) if "name: Generate signed Sparkle appcast" in line)
start = next(i for i in range(marker, len(lines)) if lines[i].strip() == "run: |") + 1
script = []
for line in lines[start:]:
    if line and not line.startswith("          "):
        break
    script.append(line[10:] if line else "")
Path(sys.argv[2]).write_text("\n".join(script) + "\n")
PY
appcast_mock_bin="$test_tmp/appcast-mock-bin"
appcast_tools="$test_tmp/appcast-tools"
mkdir -p "$appcast_mock_bin" "$appcast_tools"
cat > "$appcast_mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
output=''
write_out=false
fail_on_http=false
while (($#)); do
  case "$1" in
    --output) output=$2; shift 2 ;;
    --write-out) write_out=true; shift 2 ;;
    --fail) fail_on_http=true; shift ;;
    *) shift ;;
  esac
done
if ! $write_out; then
  printf '<!doctype html><p>prior notes</p>' > "$output"
  exit 0
fi
case "${MOCK_FEED_FETCH:-404}" in
  404) printf 404; $fail_on_http && exit 56 || exit 0 ;;
  transient) printf 000; exit 7 ;;
  200) cp "${MOCK_PRIOR_FEED:?}" "$output"; printf 200 ;;
  *) exit 64 ;;
esac
MOCK
cat > "$appcast_mock_bin/xcodebuild" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
derived=''
while (($#)); do
  if [[ "$1" == -derivedDataPath ]]; then derived=$2; shift 2; else shift; fi
done
tools="$derived/SourcePackages/artifacts/sparkle/Sparkle/bin"
mkdir -p "$tools"
cp "${MOCK_GENERATE_TOOL:?}" "$tools/generate_appcast"
cp "${MOCK_SIGN_TOOL:?}" "$tools/sign_update"
chmod +x "$tools/"*
MOCK
cat > "$appcast_tools/generate_appcast" <<'MOCK'
#!/usr/bin/env python3
import os, sys, xml.etree.ElementTree as ET
feed = sys.argv[-1]
sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", sparkle)
path = os.path.join(feed, "appcast.xml")
if os.path.exists(path):
    root = ET.parse(path).getroot()
else:
    root = ET.Element("rss", {"version": "2.0"})
    ET.SubElement(root, "channel")
channel = root.find("channel")
item = ET.SubElement(channel, "item")
ET.SubElement(item, f"{{{sparkle}}}version").text = os.environ["BUILD"]
ET.SubElement(item, f"{{{sparkle}}}shortVersionString").text = os.environ["VERSION"]
note = os.path.basename(os.environ["ZIP"][:-4]) + ".html"
ET.SubElement(item, f"{{{sparkle}}}releaseNotesLink").text = "https://youranreus.github.io/TokChan/release-notes/" + note
ET.SubElement(item, "enclosure", {
    "url": "https://github.com/" + os.environ["GITHUB_REPOSITORY"] + "/releases/download/v" + os.environ["VERSION"] + "/" + os.path.basename(os.environ["ZIP"]),
    "length": str(os.path.getsize(os.environ["ZIP"])),
    f"{{{sparkle}}}edSignature": "fixture-signature",
})
ET.ElementTree(root).write(path, encoding="utf-8", xml_declaration=True)
MOCK
cat > "$appcast_tools/generate_appcast_mutating_history" <<'MOCK'
#!/usr/bin/env python3
import os, subprocess, sys, xml.etree.ElementTree as ET
subprocess.run([os.environ["MOCK_GENERATE_BASE"], *sys.argv[1:]], check=True)
path = os.path.join(sys.argv[-1], "appcast.xml")
root = ET.parse(path)
first = root.getroot().find("./channel/item/enclosure")
first.set("length", "999")
root.write(path, encoding="utf-8", xml_declaration=True)
MOCK
cat > "$appcast_tools/sign_update" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
[[ "$1" == --verify && "$2" == --ed-key-file && -f "$3" && -f "$4" && "$5" == fixture-signature ]]
MOCK
chmod +x "$appcast_mock_bin/"* "$appcast_tools/"*
seed_file="$test_tmp/sparkle-seed"
python3 - "$seed_file" <<'PY'
import base64, sys
from pathlib import Path
Path(sys.argv[1]).write_bytes(base64.b64encode(bytes(range(32))))
PY
private_secret=$(base64 < "$seed_file" | tr -d '\r\n')
python3 - "$seed_file" "$test_tmp/sparkle-private.der" <<'PY'
import base64, sys
from pathlib import Path
seed = base64.b64decode(Path(sys.argv[1]).read_bytes())
Path(sys.argv[2]).write_bytes(bytes.fromhex("302e020100300506032b657004220420") + seed)
PY
openssl pkey -inform DER -in "$test_tmp/sparkle-private.der" -pubout -outform DER \
  -out "$test_tmp/sparkle-public.der" 2>/dev/null
public_key=$(tail -c 32 "$test_tmp/sparkle-public.der" | base64 | tr -d '\r\n')
appcast_work="$test_tmp/appcast-work"
mkdir -p "$appcast_work/TokChan.xcodeproj"
(
  cd "$appcast_work"
  env PATH="$appcast_mock_bin:$PATH" MOCK_GENERATE_TOOL="$appcast_tools/generate_appcast" \
    MOCK_SIGN_TOOL="$appcast_tools/sign_update" SPARKLE_PRIVATE_KEY_BASE64="$private_secret" \
    SPARKLE_PUBLIC_ED_KEY="$public_key" VERSION="$fixture_version" BUILD="$fixture_build" \
    ZIP="$zip" GITHUB_REPOSITORY=owner/repo bash "$appcast_step" >/dev/null
)
[[ -f "$appcast_work/pages/appcast.xml" ]]
[[ -f "$appcast_work/pages/release-notes/TokChan-v${fixture_version}-macos-universal.html" ]]
pass "appcast generation accepts only a validated first-feed 404 bootstrap and stages public files"
rm -rf "$appcast_work/pages"
prior_feed="$test_tmp/prior-appcast.xml"
cat > "$prior_feed" <<'XML'
<?xml version="1.0" encoding="utf-8"?>
<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" version="2.0"><channel><item>
<sparkle:version>16</sparkle:version><sparkle:shortVersionString>1.0.1</sparkle:shortVersionString>
<sparkle:releaseNotesLink>https://youranreus.github.io/TokChan/release-notes/TokChan-v1.0.1-macos-universal.html</sparkle:releaseNotesLink>
<enclosure url="https://github.com/owner/repo/releases/download/v1.0.1/TokChan-v1.0.1-macos-universal.zip" length="123" sparkle:edSignature="prior-signature"/>
</item></channel></rss>
XML
(
  cd "$appcast_work"
  env PATH="$appcast_mock_bin:$PATH" MOCK_FEED_FETCH=200 MOCK_PRIOR_FEED="$prior_feed" \
    MOCK_GENERATE_TOOL="$appcast_tools/generate_appcast" MOCK_SIGN_TOOL="$appcast_tools/sign_update" \
    SPARKLE_PRIVATE_KEY_BASE64="$private_secret" SPARKLE_PUBLIC_ED_KEY="$public_key" \
    VERSION="$fixture_version" BUILD="$fixture_build" ZIP="$zip" GITHUB_REPOSITORY=owner/repo \
    bash "$appcast_step" >/dev/null
)
[[ -f "$appcast_work/pages/release-notes/TokChan-v1.0.1-macos-universal.html" ]]
grep -F 'v1.0.1/TokChan-v1.0.1-macos-universal.zip' "$appcast_work/pages/appcast.xml" >/dev/null
pass "appcast generation preserves prior feed history and its hosted release notes"
rm -rf "$appcast_work/pages"
expect_failure "changed or dropped prior feed history" env PATH="$appcast_mock_bin:$PATH" \
  MOCK_FEED_FETCH=200 MOCK_PRIOR_FEED="$prior_feed" \
  MOCK_GENERATE_TOOL="$appcast_tools/generate_appcast_mutating_history" \
  MOCK_GENERATE_BASE="$appcast_tools/generate_appcast" MOCK_SIGN_TOOL="$appcast_tools/sign_update" \
  SPARKLE_PRIVATE_KEY_BASE64="$private_secret" SPARKLE_PUBLIC_ED_KEY="$public_key" \
  VERSION="$fixture_version" BUILD="$fixture_build" ZIP="$zip" GITHUB_REPOSITORY=owner/repo \
  bash -c "cd '$appcast_work' && bash '$appcast_step'"
[[ ! -e "$appcast_work/pages/appcast.xml" ]]
pass "appcast generation rejects changes to prior immutable feed entries"
expect_failure "Could not safely fetch prior appcast" env PATH="$appcast_mock_bin:$PATH" \
  MOCK_FEED_FETCH=transient MOCK_GENERATE_TOOL="$appcast_tools/generate_appcast" \
  MOCK_SIGN_TOOL="$appcast_tools/sign_update" SPARKLE_PRIVATE_KEY_BASE64="$private_secret" \
  SPARKLE_PUBLIC_ED_KEY="$public_key" VERSION="$fixture_version" BUILD="$fixture_build" \
  ZIP="$zip" GITHUB_REPOSITORY=owner/repo bash -c "cd '$appcast_work' && bash '$appcast_step'"
[[ ! -e "$appcast_work/pages/appcast.xml" ]]
pass "appcast generation fails closed on transient prior-feed errors"
expect_failure "does not match SPARKLE_PUBLIC_ED_KEY" env PATH="$appcast_mock_bin:$PATH" \
  MOCK_GENERATE_TOOL="$appcast_tools/generate_appcast" MOCK_SIGN_TOOL="$appcast_tools/sign_update" \
  SPARKLE_PRIVATE_KEY_BASE64="$private_secret" SPARKLE_PUBLIC_ED_KEY=wrong \
  VERSION="$fixture_version" BUILD="$fixture_build" ZIP="$zip" GITHUB_REPOSITORY=owner/repo \
  bash -c "cd '$appcast_work' && bash '$appcast_step'"
pass "appcast generation rejects a mismatched EdDSA keypair before feed creation"

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
    state=$(cat "${MOCK_RELEASE_STATE:?}")
    [[ "$state" == draft ]] && draft=true || draft=false
    printf '123\t%s\n' "$draft"
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
    echo "This app is Developer ID signed and Apple-notarized. The app and DMG include stapled notarization tickets. macOS may still ask you to confirm opening an app downloaded from the Internet. Verify the SHA-256 checksum before use."
  fi
elif [[ "$1" == api && " $* " == *" --jq .draft "* ]]; then
  [[ "$(cat "${MOCK_RELEASE_STATE:?}")" == draft ]] && echo true || echo false
elif [[ "$1" == api && " $* " == *"[.id, .name, .size]"* ]]; then
  printf '1\t%s\t%s\n' "${MOCK_DMG_NAME:?}" "$(stat -f %z "${MOCK_DMG_PATH:?}")"
  printf '2\t%s\t%s\n' "${MOCK_CHECKSUM_NAME:?}" "$(stat -f %z "${MOCK_CHECKSUM_PATH:?}")"
  printf '3\t%s\t%s\n' "${MOCK_ZIP_NAME:?}" "$(stat -f %z "${MOCK_ZIP_PATH:?}")"
elif [[ "$1" == api && " $* " == *'/releases/assets/'* ]]; then
  case "${!#}" in
    */1) cat "${MOCK_DMG_PATH:?}" ;;
    */2) cat "${MOCK_CHECKSUM_PATH:?}" ;;
    */3) cat "${MOCK_ZIP_PATH:?}" ;;
    *) exit 1 ;;
  esac
elif [[ "$1 $2" == 'release upload' ]]; then
  [[ -f "$4" && -f "$5" && -f "$6" ]]
else
  echo "unexpected gh invocation: $*" >&2
  exit 1
fi
MOCK
chmod +x "$workflow_mock_bin/gh"
env PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" DMG="$dmg" CHECKSUM="$checksum" ZIP="$zip" RUN_ATTEMPT=1 \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_DMG_NAME="$(basename "$dmg")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_DMG_PATH="$dmg" MOCK_CHECKSUM_PATH="$checksum" MOCK_ZIP_PATH="$zip" bash "$workflow_step" >/dev/null
[[ "$(cat "$workflow_state")" == published ]]
pass "release workflow resumes and publishes a draft by Release ID"
printf absent > "$workflow_state"
env PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" DMG="$dmg" CHECKSUM="$checksum" ZIP="$zip" RUN_ATTEMPT=1 \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_LIST_INVISIBLE=1 MOCK_DMG_NAME="$(basename "$dmg")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_DMG_PATH="$dmg" MOCK_CHECKSUM_PATH="$checksum" MOCK_ZIP_PATH="$zip" bash "$workflow_step" >/dev/null
[[ "$(cat "$workflow_state")" == published ]]
pass "release workflow publishes a new draft from the create response ID"
printf draft > "$workflow_state"
expect_failure "missing required distribution text" env \
  PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" DMG="$dmg" CHECKSUM="$checksum" ZIP="$zip" RUN_ATTEMPT=1 \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_DMG_NAME="$(basename "$dmg")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_DMG_PATH="$dmg" MOCK_CHECKSUM_PATH="$checksum" MOCK_ZIP_PATH="$zip" \
  MOCK_RELEASE_BODY='This app bundle is ad-hoc signed, not Developer ID signed, and not Apple-notarized.' \
  bash "$workflow_step"
[[ "$(cat "$workflow_state")" == draft ]]
pass "release workflow refuses a draft with incomplete distribution warnings"

printf published > "$workflow_state"
expect_failure "already published; assets are immutable" env \
  PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" DMG="$dmg" CHECKSUM="$checksum" ZIP="$zip" RUN_ATTEMPT=1 \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_DMG_NAME="$(basename "$dmg")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_DMG_PATH="$dmg" MOCK_CHECKSUM_PATH="$checksum" MOCK_ZIP_PATH="$zip" bash "$workflow_step"
[[ "$(cat "$workflow_state")" == published ]]
pass "release workflow preserves published Release immutability"
env PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" DMG="$dmg" CHECKSUM="$checksum" ZIP="$zip" RUN_ATTEMPT=2 \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_DMG_NAME="$(basename "$dmg")" \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_DMG_PATH="$dmg" MOCK_CHECKSUM_PATH="$checksum" MOCK_ZIP_PATH="$zip" bash "$workflow_step" >/dev/null
[[ "$(cat "$workflow_state")" == published ]]
pass "release workflow permits byte-verified feed-only recovery without mutating a published Release"

printf draft > "$workflow_state"
expect_failure "assets do not exactly match the expected set" env \
  PATH="$workflow_mock_bin:$PATH" \
  GITHUB_REPOSITORY=owner/repo TAG="v${fixture_version}" DMG="$dmg" CHECKSUM="$checksum" ZIP="$zip" RUN_ATTEMPT=1 \
  MOCK_RELEASE_STATE="$workflow_state" MOCK_DMG_NAME=unexpected.dmg \
  MOCK_CHECKSUM_NAME="$(basename "$checksum")" MOCK_ZIP_NAME="$(basename "$zip")" \
  MOCK_DMG_PATH="$dmg" MOCK_CHECKSUM_PATH="$checksum" MOCK_ZIP_PATH="$zip" bash "$workflow_step"
[[ "$(cat "$workflow_state")" == draft ]]
pass "release workflow refuses to publish a draft with a non-exact asset pair"

expect_failure "refusing to overwrite existing asset" env PATH="$fixture/mock-bin:$PATH" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
pass "build script refuses stale final assets"

rm -rf "$fixture/output"
mkdir -p "$fixture/output"
ln -s "$fixture/missing-user-asset" "$dmg"
expect_failure "refusing to overwrite existing asset" env PATH="$fixture/mock-bin:$PATH" \
  "$fixture/scripts/build-release.sh" --skip-tests --output output
[[ -L "$dmg" && "$(readlink "$dmg")" == "$fixture/missing-user-asset" ]]
rm -f "$dmg"
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
pass "build script removes its DMG when checksum publication fails"

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
printf fake > "dist/TokChan-v${version}-macos-universal.dmg"
printf checksum > "dist/TokChan-v${version}-macos-universal.dmg.sha256"
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

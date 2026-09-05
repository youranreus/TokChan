#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: scripts/build-release.sh [--output <directory>] [--skip-tests]" >&2
}

fail() {
  echo "build-release: $*" >&2
  exit 1
}

script_dir=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(CDPATH= cd -- "$script_dir/.." && pwd)
cd "$repo_root"

output_arg="dist"
output_seen=false
skip_tests=false
while (($#)); do
  case "$1" in
    --output)
      $output_seen && fail "--output may only be specified once"
      (($# >= 2)) || fail "--output requires a directory"
      [[ -n "$2" ]] || fail "--output requires a non-empty directory"
      output_arg=$2
      output_seen=true
      shift 2
      ;;
    --skip-tests)
      $skip_tests && fail "--skip-tests may only be specified once"
      skip_tests=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      fail "unknown argument: $1"
      ;;
  esac
done

[[ -d TokChan.xcodeproj ]] || fail "TokChan.xcodeproj was not found at $repo_root"
[[ -f TokChan.xcodeproj/xcshareddata/xcschemes/TokChan.xcscheme ]] || \
  fail "the shared TokChan scheme was not found"

for command_name in xcodebuild xcrun codesign ditto hdiutil lipo osascript shasum python3; do
  command -v "$command_name" >/dev/null 2>&1 || fail "required command not found: $command_name"
done
[[ -x /usr/libexec/PlistBuddy ]] || fail "required command not found: /usr/libexec/PlistBuddy"

case "$output_arg" in
  /*) output_dir=$output_arg ;;
  *) output_dir="$repo_root/$output_arg" ;;
esac
mkdir -p "$output_dir"
output_dir=$(CDPATH= cd -- "$output_dir" && pwd)

work_dir=$(mktemp -d "${TMPDIR:-/tmp}/tokchan-release.XXXXXX")
work_dir=$(CDPATH= cd -- "$work_dir" && pwd -P)
derived_data="$work_dir/DerivedData"
staging_dir="$work_dir/staging"
mkdir -p "$staging_dir"
build_log="$work_dir/build.log"
published_dmg=""
published_checksum=""
publish_lock=""
publish_lock_acquired=false
layout_device=""
verification_device=""
succeeded=false

cleanup() {
  local status=$?
  local failure_log cleanup_failed=false
  set +e

  # Never delete a mount point until the image owned by this run is detached.
  if [[ -n "$verification_device" ]]; then
    hdiutil detach "$verification_device" >> "$build_log" 2>&1 || cleanup_failed=true
  fi
  if [[ -n "$layout_device" ]]; then
    hdiutil detach "$layout_device" >> "$build_log" 2>&1 || cleanup_failed=true
  fi
  if $cleanup_failed; then
    status=1
  fi
  if $publish_lock_acquired; then
    rmdir -- "$publish_lock" || status=1
  fi
  if [[ $status -ne 0 ]]; then
    [[ -z "$published_checksum" ]] || rm -f -- "$published_checksum"
    [[ -z "$published_dmg" ]] || rm -f -- "$published_dmg"
  fi

  if [[ $status -eq 0 && "$succeeded" == true ]]; then
    rm -rf -- "$work_dir"
  else
    failure_log="${TMPDIR:-/tmp}/TokChan-release-failure-$(date +%Y%m%d-%H%M%S)-$$.log"
    {
      echo "TokChan release build failed with status $status."
      [[ ! -f "$build_log" ]] || cat "$build_log"
      if $cleanup_failed; then
        echo "An owned disk image could not be detached; temporary workspace retained at $work_dir."
      fi
    } > "$failure_log"
    if ! $cleanup_failed; then
      rm -rf -- "$work_dir"
    fi
    echo "build-release: failed; diagnostic log retained at $failure_log" >&2
  fi
  return "$status"
}
trap cleanup EXIT

echo "==> Environment"
sw_vers
uname -m
xcodebuild -version

read_project_version() {
  python3 scripts/lib/project-version.py TokChan.xcodeproj/project.pbxproj get
}

read_build_setting() {
  local configuration=$1
  local key=$2
  local output value count
  output=$(xcodebuild \
    -project TokChan.xcodeproj \
    -target TokChan \
    -configuration "$configuration" \
    -showBuildSettings \
    CODE_SIGNING_ALLOWED=NO)
  count=$(awk -v key="$key" '$1 == key && $2 == "=" { count++ } END { print count + 0 }' <<<"$output")
  [[ "$count" == 1 ]] || fail "expected one $key value for $configuration, found $count"
  value=$(awk -v key="$key" '$1 == key && $2 == "=" { print $3 }' <<<"$output")
  [[ -n "$value" ]] || fail "$key is empty for $configuration"
  printf '%s\n' "$value"
}

read -r source_version source_build < <(read_project_version)
debug_version=$(read_build_setting Debug MARKETING_VERSION)
release_version=$(read_build_setting Release MARKETING_VERSION)
debug_build=$(read_build_setting Debug CURRENT_PROJECT_VERSION)
release_build=$(read_build_setting Release CURRENT_PROJECT_VERSION)

[[ "$debug_version" == "$release_version" ]] || \
  fail "Debug and Release MARKETING_VERSION differ ($debug_version vs $release_version)"
[[ "$debug_build" == "$release_build" ]] || \
  fail "Debug and Release CURRENT_PROJECT_VERSION differ ($debug_build vs $release_build)"
[[ "$release_version" == "$source_version" && "$release_build" == "$source_build" ]] || \
  fail "resolved Xcode versions do not match the project version contract"
[[ "$release_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
  fail "MARKETING_VERSION must be stable SemVer, got $release_version"
[[ "$release_build" =~ ^[1-9][0-9]*$ ]] || \
  fail "CURRENT_PROJECT_VERSION must be a positive integer, got $release_build"

asset_basename="TokChan-v${release_version}-macos-universal.dmg"
checksum_basename="${asset_basename}.sha256"
final_dmg="$output_dir/$asset_basename"
final_checksum="$output_dir/$checksum_basename"
path_exists() {
  [[ -e "$1" || -L "$1" ]]
}
! path_exists "$final_dmg" || fail "refusing to overwrite existing asset: $final_dmg"
! path_exists "$final_checksum" || fail "refusing to overwrite existing asset: $final_checksum"

if ! $skip_tests; then
  echo "==> Running TokChan unit tests (UI tests are intentionally not a release gate)"
  xcodebuild test \
    -project TokChan.xcodeproj \
    -scheme TokChan \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    -only-testing:TokChanTests \
    2>&1 | tee -a "$build_log"
else
  echo "==> Skipping unit tests (local iteration only)"
fi

echo "==> Building credential-free universal Release app (Xcode signing disabled)"
xcodebuild build \
  -project TokChan.xcodeproj \
  -scheme TokChan \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "$derived_data" \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY='' \
  2>&1 | tee -a "$build_log"

app_path="$derived_data/Build/Products/Release/TokChan.app"
info_plist="$app_path/Contents/Info.plist"
executable="$app_path/Contents/MacOS/TokChan"
[[ -d "$app_path" ]] || fail "built app was not found at $app_path"
[[ -f "$info_plist" ]] || fail "built Info.plist was not found"
[[ -f "$executable" ]] || fail "built executable was not found"

bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info_plist")
bundle_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info_plist")
bundle_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info_plist")
[[ "$bundle_version" == "$release_version" ]] || \
  fail "bundle version $bundle_version does not match $release_version"
[[ "$bundle_build" == "$release_build" ]] || \
  fail "bundle build $bundle_build does not match $release_build"
[[ "$bundle_identifier" == "com.youranreus.TokChan" ]] || \
  fail "unexpected bundle identifier: $bundle_identifier"

architectures=" $(lipo -archs "$executable") "
[[ "$architectures" == *" arm64 "* ]] || fail "main executable does not contain arm64"
[[ "$architectures" == *" x86_64 "* ]] || fail "main executable does not contain x86_64"

signature_metadata_value() {
  local metadata=$1
  local field=$2
  awk -v prefix="$field=" '
    index($0, prefix) == 1 {
      count++
      value = substr($0, length(prefix) + 1)
    }
    END {
      if (count != 1) exit 1
      print value
    }
  ' <<<"$metadata"
}

verify_signed_bundle() {
  local bundle_path=$1
  local expected_identifier=$2
  local signature_metadata metadata_identifier signature_kind info_entries team_identifier
  local sealed_resources

  if ! codesign --verify --deep --strict --verbose=2 "$bundle_path" 2>&1 | tee -a "$build_log"; then
    fail "strict signature verification failed for $bundle_path"
  fi
  if ! signature_metadata=$(codesign -dv --verbose=4 "$bundle_path" 2>&1); then
    printf '%s\n' "$signature_metadata" >> "$build_log"
    fail "could not inspect signature metadata for $bundle_path"
  fi
  printf '%s\n' "$signature_metadata" >> "$build_log"

  if ! metadata_identifier=$(signature_metadata_value "$signature_metadata" Identifier); then
    fail "signature metadata does not contain exactly one Identifier for $bundle_path"
  fi
  [[ "$metadata_identifier" == "$expected_identifier" ]] || \
    fail "signature metadata has unexpected identifier $metadata_identifier for $bundle_path"

  if ! signature_kind=$(signature_metadata_value "$signature_metadata" Signature); then
    fail "signature metadata does not contain exactly one Signature for $bundle_path"
  fi
  [[ "$signature_kind" == adhoc ]] || \
    fail "signature metadata is not a complete ad-hoc signature for $bundle_path"

  if ! team_identifier=$(signature_metadata_value "$signature_metadata" TeamIdentifier); then
    fail "signature metadata does not contain exactly one TeamIdentifier for $bundle_path"
  fi
  [[ "$team_identifier" == "not set" ]] || \
    fail "ad-hoc signature unexpectedly has TeamIdentifier $team_identifier for $bundle_path"

  if ! info_entries=$(signature_metadata_value "$signature_metadata" "Info.plist entries"); then
    fail "signature metadata does not contain exactly one Info.plist entry count for $bundle_path"
  fi
  [[ "$info_entries" =~ ^[1-9][0-9]*$ ]] || \
    fail "signature metadata does not cover Info.plist for $bundle_path"

  if ! sealed_resources=$(signature_metadata_value "$signature_metadata" "Sealed Resources version"); then
    fail "signature metadata does not contain exactly one sealed-resources record for $bundle_path"
  fi
  [[ "$sealed_resources" =~ ^[1-9][0-9]*\ rules=[0-9]+\ files=[1-9][0-9]*$ ]] || \
    fail "signature metadata does not contain sealed resources for $bundle_path"
}

echo "==> Ad-hoc signing complete app bundle"
codesign --force --sign - --identifier "$bundle_identifier" "$app_path" || \
  fail "ad-hoc bundle signing failed"
verify_signed_bundle "$app_path" "$bundle_identifier"

verify_app_contract() {
  local candidate_app=$1
  local candidate_plist="$candidate_app/Contents/Info.plist"
  local candidate_executable="$candidate_app/Contents/MacOS/TokChan"
  local candidate_version candidate_build candidate_identifier candidate_architectures

  [[ -d "$candidate_app" && ! -L "$candidate_app" ]] || \
    fail "expected app was not found in disk image"
  [[ -f "$candidate_plist" ]] || fail "disk image app Info.plist was not found"
  [[ -f "$candidate_executable" ]] || fail "disk image app executable was not found"
  candidate_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$candidate_plist")
  candidate_build=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$candidate_plist")
  candidate_identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$candidate_plist")
  [[ "$candidate_version" == "$release_version" ]] || \
    fail "disk image app version $candidate_version does not match $release_version"
  [[ "$candidate_build" == "$release_build" ]] || \
    fail "disk image app build $candidate_build does not match $release_build"
  [[ "$candidate_identifier" == "$bundle_identifier" ]] || \
    fail "disk image app has unexpected bundle identifier $candidate_identifier"
  candidate_architectures=" $(lipo -archs "$candidate_executable") "
  [[ "$candidate_architectures" == *" arm64 "* ]] || \
    fail "disk image app executable does not contain arm64"
  [[ "$candidate_architectures" == *" x86_64 "* ]] || \
    fail "disk image app executable does not contain x86_64"
  verify_signed_bundle "$candidate_app" "$bundle_identifier"
}

read_attachment() {
  local plist_path=$1
  local expected_mount=$2
  python3 - "$plist_path" "$expected_mount" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as stream:
    payload = plistlib.load(stream)
matches = [
    (entity.get("dev-entry"), entity.get("mount-point"))
    for entity in payload.get("system-entities", [])
    if entity.get("mount-point") == sys.argv[2]
]
if len(matches) != 1 or not matches[0][0]:
    raise SystemExit("attach plist did not contain exactly one expected mounted device")
print(f"{matches[0][0]}\t{matches[0][1]}")
PY
}

attached_mount=""
attach_image() {
  local image=$1
  local mount_point=$2
  local mode=$3
  local plist_path=$4
  local tracking_variable=$5
  local attachment parsed_device parsed_mount
  local -a options=(-noautoopen -mountpoint "$mount_point" -plist)
  if [[ "$mode" == readonly ]]; then
    options=(-readonly -nobrowse "${options[@]}")
  fi
  # Track the private mount path before attach so even a partial attach is cleaned up.
  printf -v "$tracking_variable" '%s' "$mount_point"
  if ! hdiutil attach "${options[@]}" "$image" > "$plist_path"; then
    if hdiutil detach "$mount_point" >> "$build_log" 2>&1; then
      printf -v "$tracking_variable" '%s' ""
    elif [[ -z "$(find "$mount_point" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
      # attach failed before mounting anything; the private directory is still empty.
      printf -v "$tracking_variable" '%s' ""
    fi
    fail "could not attach disk image for $mode access"
  fi
  if ! attachment=$(read_attachment "$plist_path" "$mount_point"); then
    fail "could not identify owned $mode disk image attachment"
  fi
  IFS=$'\t' read -r parsed_device parsed_mount <<< "$attachment"
  [[ -n "$parsed_device" && "$parsed_mount" == "$mount_point" ]] || \
    fail "$mode disk image was not attached at the owned mount point"
  printf -v "$tracking_variable" '%s' "$parsed_device"
  attached_mount=$parsed_mount
}

detach_image() {
  local device=$1
  local purpose=$2
  if ! hdiutil detach "$device" >> "$build_log" 2>&1; then
    fail "could not detach $purpose disk image"
  fi
}

echo "==> Creating DMG and Finder layout"
dmg_root="$work_dir/dmg-root"
layout_mount="$work_dir/layout-mount"
verification_mount="$work_dir/verification-mount"
writable_dmg="$work_dir/TokChan-writable.dmg"
staged_dmg="$staging_dir/$asset_basename"
staged_checksum="$staging_dir/$checksum_basename"
mkdir -p "$dmg_root" "$layout_mount" "$verification_mount"
ditto "$app_path" "$dmg_root/TokChan.app"
ln -s /Applications "$dmg_root/Applications"
[[ "$(readlink "$dmg_root/Applications")" == /Applications ]] || \
  fail "could not stage the Applications symlink"

hdiutil create -quiet -fs HFS+ -format UDRW -volname TokChan \
  -srcfolder "$dmg_root" "$writable_dmg" || fail "could not create writable disk image"
attach_image "$writable_dmg" "$layout_mount" readwrite \
  "$work_dir/layout-attach.plist" layout_device
[[ "$attached_mount" == "$layout_mount" ]] || \
  fail "writable disk image was not attached at the owned mount point"

if ! osascript - "$layout_mount" <<'APPLESCRIPT'
on run argv
  set mountPath to item 1 of argv
  with timeout of 20 seconds
    tell application "Finder"
      set targetFolder to POSIX file mountPath as alias
      open targetFolder
      set targetWindow to container window of targetFolder
      set current view of targetWindow to icon view
      set toolbar visible of targetWindow to false
      set statusbar visible of targetWindow to false
      set bounds of targetWindow to {100, 100, 650, 430}
      set viewOptions to icon view options of targetWindow
      set arrangement of viewOptions to not arranged
      set icon size of viewOptions to 96
      set text size of viewOptions to 12
      set position of item "TokChan.app" of targetFolder to {140, 160}
      set position of item "Applications" of targetFolder to {410, 160}
      update targetFolder without registering applications
      delay 1
      close targetWindow
    end tell
  end timeout
end run
APPLESCRIPT
then
  fail "could not configure Finder disk image layout"
fi
layout_written=false
for _ in {1..40}; do
  if [[ -f "$layout_mount/.DS_Store" ]]; then
    layout_written=true
    break
  fi
  sleep 0.25
done
$layout_written || fail "Finder did not persist disk image layout metadata"
sync
detach_image "$layout_device" writable
layout_device=""

hdiutil convert "$writable_dmg" -quiet -format UDZO -imagekey zlib-level=9 \
  -o "$staged_dmg" || fail "could not create compressed disk image"
hdiutil verify "$staged_dmg" >> "$build_log" 2>&1 || fail "disk image verification failed"

attach_image "$staged_dmg" "$verification_mount" readonly \
  "$work_dir/verification-attach.plist" verification_device
[[ "$attached_mount" == "$verification_mount" ]] || \
  fail "compressed disk image was not attached at the owned mount point"
[[ -L "$verification_mount/Applications" ]] || \
  fail "disk image Applications entry is not a symbolic link"
[[ "$(readlink "$verification_mount/Applications")" == /Applications ]] || \
  fail "disk image Applications entry does not point to /Applications"
[[ -d "$verification_mount/TokChan.app" && ! -L "$verification_mount/TokChan.app" ]] || \
  fail "expected app was not found in disk image"
python3 - "$verification_mount" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])
visible = sorted(item.name for item in root.iterdir() if not item.name.startswith("."))
expected = ["Applications", "TokChan.app"]
if visible != expected:
    raise SystemExit(f"unexpected user-visible disk image entries: {visible}")
PY
verify_app_contract "$verification_mount/TokChan.app"
detach_image "$verification_device" verification
verification_device=""

(
  cd "$staging_dir"
  shasum -a 256 "$asset_basename" > "$checksum_basename"
  shasum -a 256 -c "$checksum_basename"
)

# Serialize only final publication. Concurrent builds may proceed, but just one may
# claim these final names, and files created before this run are never overwritten.
publish_lock="$output_dir/.${asset_basename}.publishing"
if mkdir -- "$publish_lock" 2>/dev/null; then
  publish_lock_acquired=true
else
  fail "another publication may be using this asset name: $publish_lock"
fi
! path_exists "$final_dmg" || fail "refusing to overwrite existing asset: $final_dmg"
! path_exists "$final_checksum" || fail "refusing to overwrite existing asset: $final_checksum"

# Publish the pair last. Paths are marked as ours before moving so interruption
# during either move cannot leave final-named partial output behind.
published_dmg=$final_dmg
published_checksum=$final_checksum
mv -- "$staged_dmg" "$final_dmg"
mv -- "$staged_checksum" "$final_checksum"
succeeded=true

echo "==> Release assets"
echo "$final_dmg"
echo "$final_checksum"
echo "WARNING: This app bundle is ad-hoc signed, not Developer ID signed, and not Apple-notarized."
echo "Ad-hoc signing provides bundle integrity but no verified developer identity; Gatekeeper may block or warn on launch."
echo "This release format is intended only for the maintainer's personal use, not ordinary public distribution."

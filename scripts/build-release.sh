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

for command_name in xcodebuild xcrun codesign ditto lipo shasum unzip python3; do
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
derived_data="$work_dir/DerivedData"
staging_dir="$work_dir/staging"
mkdir -p "$staging_dir"
build_log="$work_dir/build.log"
published_zip=""
published_checksum=""
publish_lock=""
publish_lock_acquired=false
succeeded=false

cleanup() {
  local status=$?
  local failure_log
  set +e
  if [[ $status -ne 0 ]]; then
    [[ -z "$published_checksum" ]] || rm -f -- "$published_checksum"
    [[ -z "$published_zip" ]] || rm -f -- "$published_zip"
  fi
  if $publish_lock_acquired; then
    rmdir -- "$publish_lock"
  fi
  if [[ $status -eq 0 && "$succeeded" == true ]]; then
    rm -rf -- "$work_dir"
  else
    failure_log="${TMPDIR:-/tmp}/TokChan-release-failure-$(date +%Y%m%d-%H%M%S)-$$.log"
    {
      echo "TokChan release build failed with status $status."
      [[ ! -f "$build_log" ]] || cat "$build_log"
    } > "$failure_log"
    rm -rf -- "$work_dir"
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

asset_basename="TokChan-v${release_version}-macos-universal.zip"
checksum_basename="${asset_basename}.sha256"
final_zip="$output_dir/$asset_basename"
final_checksum="$output_dir/$checksum_basename"
path_exists() {
  [[ -e "$1" || -L "$1" ]]
}
! path_exists "$final_zip" || fail "refusing to overwrite existing asset: $final_zip"
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

echo "==> Packaging and reverifying signed app"
staged_zip="$staging_dir/$asset_basename"
staged_checksum="$staging_dir/$checksum_basename"
verification_dir="$work_dir/verification"
ditto -c -k --keepParent "$app_path" "$staged_zip"
unzip -t "$staged_zip" >/dev/null
mkdir -p "$verification_dir"
ditto -x -k "$staged_zip" "$verification_dir"
extracted_app="$verification_dir/TokChan.app"
[[ -d "$extracted_app" ]] || fail "expected app was not found after ZIP extraction"
verify_signed_bundle "$extracted_app" "$bundle_identifier"
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
! path_exists "$final_zip" || fail "refusing to overwrite existing asset: $final_zip"
! path_exists "$final_checksum" || fail "refusing to overwrite existing asset: $final_checksum"

# Publish the pair last. Paths are marked as ours before moving so interruption
# during either move cannot leave final-named partial output behind.
published_zip=$final_zip
published_checksum=$final_checksum
mv -- "$staged_zip" "$final_zip"
mv -- "$staged_checksum" "$final_checksum"
succeeded=true

echo "==> Release assets"
echo "$final_zip"
echo "$final_checksum"
echo "WARNING: This app bundle is ad-hoc signed, not Developer ID signed, and not Apple-notarized."
echo "Ad-hoc signing provides bundle integrity but no verified developer identity; Gatekeeper may block or warn on launch."
echo "This release format is intended only for the maintainer's personal use, not ordinary public distribution."

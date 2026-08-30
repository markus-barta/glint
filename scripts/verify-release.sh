#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
app="$repo_dir/dist/Nuncid.app"
archive="$repo_dir/dist/Nuncid-$version.zip"
plist="$app/Contents/Info.plist"

"$repo_dir/scripts/check-release-consistency.sh"
[[ -d "$app" ]] || { print -u2 "Missing $app"; exit 1; }
[[ -f "$archive" ]] || { print -u2 "Missing $archive"; exit 1; }

bundle_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$plist")
[[ "$bundle_version" == "$version" ]] || { print -u2 "Bundle version $bundle_version does not match $version"; exit 1; }
codesign --verify --deep --strict "$app"
unzip -tq "$archive" >/dev/null

signing_mode=$(/usr/libexec/PlistBuddy -c 'Print :NuncidSigningMode' "$plist")
signature_details=$(codesign -dv --verbose=4 "$app" 2>&1)
case "$signing_mode" in
  ad-hoc)
    [[ "$signature_details" == *$'\nSignature=adhoc\n'* ]] || {
      print -u2 'Bundle declares ad-hoc signing but its signature disagrees.'
      exit 1
    }
    [[ "${NUNCID_EXPECT_NOTARIZED:-0}" != 1 ]] || {
      print -u2 'An ad-hoc build cannot satisfy NUNCID_EXPECT_NOTARIZED=1.'
      exit 1
    }
    ;;
  developer-id)
    [[ "$signature_details" == *$'\nAuthority=Developer ID Application:'* ]] || {
      print -u2 'Bundle declares Developer ID signing but its signature disagrees.'
      exit 1
    }
    if [[ "${NUNCID_EXPECT_NOTARIZED:-0}" == 1 ]]; then
      xcrun stapler validate "$app"
    fi
    ;;
  *) print -u2 "Unknown NuncidSigningMode: $signing_mode"; exit 1 ;;
esac

self_test_dir=$(mktemp -d)
trap 'rm -rf "$self_test_dir"' EXIT
(
  cd "$self_test_dir"
  "$app/Contents/MacOS/Nuncid" --self-test
)

print -r -- "Verified Nuncid $version package ($signing_mode signing)"

#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
archive="$repo_dir/dist/Nuncid-$version.zip"
temporary_archive="$repo_dir/dist/.Nuncid-$version.$$.zip"
notary_profile=${NUNCID_NOTARY_PROFILE:-}
signing_identity=${NUNCID_SIGNING_IDENTITY:--}

trap 'rm -f "$temporary_archive"' EXIT
if [[ -n "$notary_profile" && "$signing_identity" == "-" ]]; then
  print -u2 'NUNCID_NOTARY_PROFILE requires NUNCID_SIGNING_IDENTITY.'
  exit 1
fi
"$repo_dir/scripts/package-app.sh" release
ditto -c -k --sequesterRsrc --keepParent "$repo_dir/dist/Nuncid.app" "$temporary_archive"
if [[ -n "$notary_profile" ]]; then
  xcrun notarytool submit "$temporary_archive" --keychain-profile "$notary_profile" --wait
  xcrun stapler staple "$repo_dir/dist/Nuncid.app"
  xcrun stapler validate "$repo_dir/dist/Nuncid.app"
  rm -f "$temporary_archive"
  ditto -c -k --sequesterRsrc --keepParent "$repo_dir/dist/Nuncid.app" "$temporary_archive"
  print -r -- 'Developer ID build notarized and ticket stapled.' >&2
fi
mv -f "$temporary_archive" "$archive"
echo "$archive"

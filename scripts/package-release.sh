#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
archive="$repo_dir/dist/Glint-$version.zip"
temporary_archive="$repo_dir/dist/.Glint-$version.$$.zip"

trap 'rm -f "$temporary_archive"' EXIT
"$repo_dir/scripts/package-app.sh" release
ditto -c -k --sequesterRsrc --keepParent "$repo_dir/dist/Glint.app" "$temporary_archive"
mv -f "$temporary_archive" "$archive"
echo "$archive"

#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
readme="$repo_dir/README.md"
changelog="$repo_dir/CHANGELOG.md"
history_file="$repo_dir/Sources/Nuncid/ReleaseHistory.swift"

if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Invalid semantic version in VERSION: $version"
  exit 1
fi

grep -q "release-$version-" "$readme" || { print -u2 "README release badge does not match $version"; exit 1; }
grep -q "Latest release $version" "$readme" || { print -u2 "README release badge alt text does not match $version"; exit 1; }
grep -q "^## \[$version\]" "$changelog" || { print -u2 "CHANGELOG is missing $version"; exit 1; }

changelog_pairs=$(sed -n 's/^## \[\([0-9][0-9.]*\)\] - \([0-9][0-9-]*\)$/\1|\2/p' "$changelog")
history_pairs=$(awk '
  /^[[:space:]]*version: "[0-9]/ {
    value = $0
    sub(/^[^"]*"/, "", value)
    sub(/".*$/, "", value)
    release = value
    next
  }
  /^[[:space:]]*isoDate: "/ && release != "" {
    value = $0
    sub(/^[^"]*"/, "", value)
    sub(/".*$/, "", value)
    print release "|" value
    release = ""
  }
' "$history_file")
if [[ "$changelog_pairs" != "$history_pairs" ]]; then
  print -u2 'CHANGELOG and in-app Release History version/date lists disagree.'
  exit 1
fi

history_version=$(sed -n 's/^[[:space:]]*version: "\([0-9][^"]*\)",/\1/p' "$history_file" | head -1)
if [[ "$history_version" != "$version" ]]; then
  print -u2 "Release History starts at $history_version, expected $version"
  exit 1
fi

download_references=$(grep -oE 'releases/download/v[0-9]+\.[0-9]+\.[0-9]+' "$readme") || {
  grep_status=$?
  if (( grep_status != 1 )); then
    print -u2 "Could not inspect README download references (grep exit $grep_status)."
    exit 1
  fi
  download_references=""
}
for reference in ${(f)download_references}; do
  referenced_version=${reference##*/v}
  if [[ "$referenced_version" != "$version" ]]; then
    print -u2 "README download points at $referenced_version, expected $version or releases/latest"
    exit 1
  fi
done

for stem in hero workflow lookup-highlight settings-showcase version-history; do
  grep -q "docs/screenshots/$stem-$version.png" "$readme" || {
    print -u2 "README does not reference current $stem-$version.png"
    exit 1
  }
  [[ -f "$repo_dir/docs/screenshots/$stem-$version.png" ]] || {
    print -u2 "Missing docs/screenshots/$stem-$version.png"
    exit 1
  }
done

for stem in pinned-card settings-scanning settings-pinned settings-appearance version-history-dark social-preview; do
  [[ -f "$repo_dir/docs/screenshots/$stem-$version.png" ]] || {
    print -u2 "Missing docs/screenshots/$stem-$version.png"
    exit 1
  }
done

social_size=$(wc -c < "$repo_dir/docs/screenshots/social-preview-$version.png" | tr -d '[:space:]')
if (( social_size >= 1000000 )); then
  print -u2 "Social preview must stay below GitHub's 1 MB limit ($social_size bytes)"
  exit 1
fi

print -r -- "Nuncid release consistency passed ($version)"

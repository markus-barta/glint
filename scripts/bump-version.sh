#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
bump=${1:-patch}
summary=${2:-}
version_file="$repo_dir/VERSION"
changelog_file="$repo_dir/CHANGELOG.md"
readme_file="$repo_dir/README.md"

if [[ -z "$summary" ]]; then
  print -u2 'Usage: scripts/bump-version.sh major|minor|patch "release summary"'
  exit 2
fi

current=$(tr -d '[:space:]' < "$version_file")
if [[ ! "$current" =~ '^([0-9]+)\.([0-9]+)\.([0-9]+)$' ]]; then
  print -u2 "Invalid semantic version in VERSION: $current"
  exit 1
fi

major=${match[1]}
minor=${match[2]}
patch=${match[3]}
case "$bump" in
  major) (( major += 1 )); minor=0; patch=0 ;;
  minor) (( minor += 1 )); patch=0 ;;
  patch) (( patch += 1 )) ;;
  *) print -u2 "Unknown bump: $bump (expected major, minor, or patch)"; exit 2 ;;
esac
next="$major.$minor.$patch"
current_pattern=${current//./\\.}

if grep -q "^## \[$next\]" "$changelog_file"; then
  print -u2 "CHANGELOG.md already contains $next"
  exit 1
fi
if [[ ! -f "$readme_file" ]] || ! grep -q "release-$current-" "$readme_file"; then
  print -u2 "README.md is missing the current release badge: $current"
  exit 1
fi

task_tmp_dir=$(mktemp -d)
trap 'rm -rf "$task_tmp_dir"' EXIT
task_changelog="$task_tmp_dir/CHANGELOG.md"
task_readme="$task_tmp_dir/README.md"
awk -v version="$next" -v release_date="$(date +%F)" -v summary="$summary" '
  { print }
  !inserted && $0 == "## [Unreleased]" {
    print ""
    print "## [" version "] - " release_date
    print ""
    print "- " summary
    inserted = 1
  }
' "$changelog_file" > "$task_changelog"

if ! grep -q "^## \[$next\]" "$task_changelog"; then
  print -u2 'CHANGELOG.md is missing the canonical Unreleased heading'
  exit 1
fi

awk -v current="$current" -v current_pattern="$current_pattern" -v next_version="$next" '
  {
    gsub("release-" current "-", "release-" next_version "-")
    gsub("Latest release " current, "Latest release " next_version)
    gsub("-" current_pattern "\\.png", "-" next_version ".png")
    print
  }
' "$readme_file" > "$task_readme"

if ! grep -q "release-$next-" "$task_readme" || ! grep -q "Latest release $next" "$task_readme"; then
  print -u2 "Could not update the README release badge to $next"
  exit 1
fi
for stem in hero workflow lookup-highlight settings-showcase version-history; do
  if ! grep -q "docs/screenshots/$stem-$next.png" "$task_readme"; then
    print -u2 "Could not update the README $stem image to $next"
    exit 1
  fi
done

mv "$task_changelog" "$changelog_file"
mv "$task_readme" "$readme_file"
print -r -- "$next" > "$version_file"
print -r -- "$next"

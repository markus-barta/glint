#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"
swift build -Xswiftc -warnings-as-errors
"$repo_dir/scripts/check-release-consistency.sh"

task_tmp_dir=$(mktemp -d)
trap 'rm -rf "$task_tmp_dir"' EXIT
self_test_dir="$task_tmp_dir/self-test"
mkdir -p "$self_test_dir"
(
  cd "$self_test_dir"
  "$repo_dir/.build/debug/Nuncid" --self-test
)

mkdir -p "$task_tmp_dir/scripts"
cp "$repo_dir/scripts/bump-version.sh" "$task_tmp_dir/scripts/bump-version.sh"
chmod +x "$task_tmp_dir/scripts/bump-version.sh"
print -r -- '1.2.3' > "$task_tmp_dir/VERSION"
print -r -- '<img src="https://img.shields.io/badge/release-1.2.3-blue" alt="Latest release 1.2.3">
<img src="docs/screenshots/hero-1.2.3.png">
<img src="docs/screenshots/workflow-1.2.3.png">
<img src="docs/screenshots/lookup-highlight-1.2.3.png">
<img src="docs/screenshots/settings-showcase-1.2.3.png">
<img src="docs/screenshots/version-history-1.2.3.png">' > "$task_tmp_dir/README.md"
print -r -- '# Changelog

## [Unreleased]

## [1.2.3] - 2026-01-01

- Previous.' > "$task_tmp_dir/CHANGELOG.md"

next=$("$task_tmp_dir/scripts/bump-version.sh" minor 'Better hover cards.')
[[ "$next" == '1.3.0' ]]
[[ "$(tr -d '[:space:]' < "$task_tmp_dir/VERSION")" == '1.3.0' ]]
grep -q '^## \[1.3.0\]' "$task_tmp_dir/CHANGELOG.md"
grep -q '^- Better hover cards\.$' "$task_tmp_dir/CHANGELOG.md"
grep -q '^## \[1.2.3\]' "$task_tmp_dir/CHANGELOG.md"
grep -q 'release-1.3.0-' "$task_tmp_dir/README.md"
grep -q 'Latest release 1.3.0' "$task_tmp_dir/README.md"
grep -q 'docs/screenshots/hero-1.3.0.png' "$task_tmp_dir/README.md"
grep -q 'docs/screenshots/workflow-1.3.0.png' "$task_tmp_dir/README.md"
grep -q 'docs/screenshots/lookup-highlight-1.3.0.png' "$task_tmp_dir/README.md"
grep -q 'docs/screenshots/settings-showcase-1.3.0.png' "$task_tmp_dir/README.md"
grep -q 'docs/screenshots/version-history-1.3.0.png' "$task_tmp_dir/README.md"
print 'Nuncid versioning tests passed'

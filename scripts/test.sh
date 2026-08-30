#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
cd "$repo_dir"
swift build
"$repo_dir/.build/debug/Nuncid" --self-test

task_tmp_dir=$(mktemp -d)
trap 'rm -rf "$task_tmp_dir"' EXIT
mkdir -p "$task_tmp_dir/scripts"
cp "$repo_dir/scripts/bump-version.sh" "$task_tmp_dir/scripts/bump-version.sh"
chmod +x "$task_tmp_dir/scripts/bump-version.sh"
print -r -- '1.2.3' > "$task_tmp_dir/VERSION"
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
print 'Nuncid versioning tests passed'

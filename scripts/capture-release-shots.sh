#!/bin/zsh
set -euo pipefail

repo_dir=${0:A:h:h}
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
screenshots="$repo_dir/docs/screenshots"
capture_dir=$(mktemp -d)
trap 'rm -rf "$capture_dir"' EXIT

cd "$repo_dir"
swift build -Xswiftc -warnings-as-errors
binary="$repo_dir/.build/debug/Nuncid"

capture_probe() {
  local stem=$1
  shift
  local output="$capture_dir/$stem-$version.png"
  "$binary" "$@" "$output" >/dev/null 2>&1 &
  local probe_pid=$!
  local probe_try
  for probe_try in {1..100}; do
    [[ -s "$output" ]] && break
    sleep 0.1
  done
  kill "$probe_pid" 2>/dev/null || true
  wait "$probe_pid" 2>/dev/null || true
  [[ -s "$output" ]] || { print -u2 "Capture failed: $stem"; return 1; }
}

capture_probe pinned-card --overlay-probe --overlay-stress-probe --overlay-capture-probe
capture_probe settings-scanning --settings-capture-probe
capture_probe settings-appearance --settings-appearance-probe --settings-capture-probe
capture_probe version-history --version-history-probe --version-history-capture-probe
capture_probe version-history-dark --version-history-probe --version-history-dark-probe --version-history-capture-probe

for stem in pinned-card settings-scanning settings-appearance version-history version-history-dark; do
  mv "$capture_dir/$stem-$version.png" "$screenshots/$stem-$version.png"
done
print -r -- "Captured Nuncid $version release visuals"

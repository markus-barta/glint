#!/bin/zsh
set -euo pipefail
repo_dir=${0:A:h:h}
configuration=${1:-release}
cd "$repo_dir"
version=$(tr -d '[:space:]' < "$repo_dir/VERSION")
if [[ ! "$version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  print -u2 "Invalid semantic version in VERSION: $version"
  exit 1
fi
build_number=$(git -C "$repo_dir" rev-list --count HEAD)
swift build -c "$configuration"
binary_dir=$(cd "$repo_dir" && swift build -c "$configuration" --show-bin-path)
app_dir="$repo_dir/dist/Glint.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Resources"
cp "$binary_dir/Glint" "$app_dir/Contents/MacOS/Glint"
chmod +x "$app_dir/Contents/MacOS/Glint"
/usr/libexec/PlistBuddy -c 'Clear dict' "$app_dir/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Glint' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string at.markusbarta.glint' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string GLINT' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleShortVersionString string $version" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $build_number" "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 13.0' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :LSUIElement bool true' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSScreenCaptureUsageDescription string GLINT reads a small cursor-adjacent crop locally to recognize ticket keys.' "$app_dir/Contents/Info.plist"
codesign --force --sign - \
  --requirements '=designated => identifier "at.markusbarta.glint"' \
  "$app_dir"
echo "$app_dir"

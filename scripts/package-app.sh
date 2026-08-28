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
rm -rf "$app_dir/Contents/Resources/Brand"
cp -R "$repo_dir/Sources/Glint/Resources/Brand" "$app_dir/Contents/Resources/Brand"
chmod +x "$app_dir/Contents/MacOS/Glint"
icon_work=$(mktemp -d)
trap 'rm -rf "$icon_work"' EXIT
iconset="$icon_work/Glint.iconset"
mkdir -p "$iconset"
app_icon="$repo_dir/Sources/Glint/Resources/Brand/glint-app-icon-1024.png"
for spec in '16 icon_16x16.png' '32 icon_16x16@2x.png' '32 icon_32x32.png' '64 icon_32x32@2x.png' '128 icon_128x128.png' '256 icon_128x128@2x.png' '256 icon_256x256.png' '512 icon_256x256@2x.png' '512 icon_512x512.png' '1024 icon_512x512@2x.png'; do
  size=${spec%% *}
  name=${spec#* }
  sips -z "$size" "$size" "$app_icon" --out "$iconset/$name" >/dev/null
done
iconutil -c icns "$iconset" -o "$app_dir/Contents/Resources/Glint.icns"
/usr/libexec/PlistBuddy -c 'Clear dict' "$app_dir/Contents/Info.plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c 'Add :CFBundleExecutable string Glint' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string at.markusbarta.glint' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleName string GLINT' "$app_dir/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string Glint' "$app_dir/Contents/Info.plist"
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

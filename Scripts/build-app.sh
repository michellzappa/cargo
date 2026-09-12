#!/bin/zsh

set -euo pipefail

scriptDirectory="$(cd "$(dirname "$0")" && pwd)"
projectDirectory="$(cd "$scriptDirectory/.." && pwd)"
versionFile="$projectDirectory/Resources/Cargo-Version.env"
source "$versionFile"
buildNumber="$(git -C "$projectDirectory" rev-list --count HEAD)"
swift build --package-path "$projectDirectory" -c release
binaryDirectory="$(swift build --package-path "$projectDirectory" -c release --show-bin-path)"
appDirectory="$projectDirectory/build/Cargo.app"

mkdir -p "$appDirectory/Contents/MacOS"
cp "$binaryDirectory/Cargo" "$appDirectory/Contents/MacOS/Cargo"
cp "$projectDirectory/Resources/Cargo-Info.plist" "$appDirectory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CARGO_VERSION" "$appDirectory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$appDirectory/Contents/Info.plist"
chmod +x "$appDirectory/Contents/MacOS/Cargo"
/usr/bin/xattr -cr "$appDirectory"
/usr/bin/xattr -dr com.apple.FinderInfo "$appDirectory" 2>/dev/null || true
/usr/bin/xattr -dr 'com.apple.fileprovider.fpfs#P' "$appDirectory" 2>/dev/null || true
codesign --force --deep --sign - --timestamp=none "$appDirectory"
/usr/bin/xattr -dr com.apple.FinderInfo "$appDirectory" 2>/dev/null || true
/usr/bin/xattr -dr 'com.apple.fileprovider.fpfs#P' "$appDirectory" 2>/dev/null || true
codesign --verify --deep --strict "$appDirectory"

printf '%s (version %s, build %s)\n' "$appDirectory" "$CARGO_VERSION" "$buildNumber"

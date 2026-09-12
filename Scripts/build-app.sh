#!/bin/zsh

set -euo pipefail

scriptDirectory="$(cd "$(dirname "$0")" && pwd)"
projectDirectory="$(cd "$scriptDirectory/.." && pwd)"
versionFile="$projectDirectory/Resources/Cargo-Version.env"
source "$versionFile"
buildNumber="$(git -C "$projectDirectory" rev-list --count HEAD)"
swift build --package-path "$projectDirectory" -c release
binaryDirectory="$(swift build --package-path "$projectDirectory" -c release --show-bin-path)"
stagingAppDirectory="$projectDirectory/build/Cargo.app"
appDirectory="/Users/mz/Applications/Cargo.app"

mkdir -p "$stagingAppDirectory/Contents/MacOS" "/Users/mz/Applications"
cp "$binaryDirectory/Cargo" "$stagingAppDirectory/Contents/MacOS/Cargo"
cp "$projectDirectory/Resources/Cargo-Info.plist" "$stagingAppDirectory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $CARGO_VERSION" "$stagingAppDirectory/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $buildNumber" "$stagingAppDirectory/Contents/Info.plist"
chmod +x "$stagingAppDirectory/Contents/MacOS/Cargo"
/usr/bin/ditto "$stagingAppDirectory" "$appDirectory"
/usr/bin/xattr -cr "$appDirectory"
/usr/bin/xattr -dr com.apple.FinderInfo "$appDirectory" 2>/dev/null || true
/usr/bin/xattr -dr 'com.apple.fileprovider.fpfs#P' "$appDirectory" 2>/dev/null || true
codesign --force --deep --sign - --timestamp=none "$appDirectory"
/usr/bin/xattr -dr com.apple.FinderInfo "$appDirectory" 2>/dev/null || true
/usr/bin/xattr -dr 'com.apple.fileprovider.fpfs#P' "$appDirectory" 2>/dev/null || true
codesign --verify --deep --strict "$appDirectory"

printf '%s (version %s, build %s)\n' "$appDirectory" "$CARGO_VERSION" "$buildNumber"

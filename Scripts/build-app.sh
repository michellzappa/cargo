#!/bin/zsh

set -euo pipefail

scriptDirectory="$(cd "$(dirname "$0")" && pwd)"
projectDirectory="$(cd "$scriptDirectory/.." && pwd)"
binaryDirectory="$(swift build --package-path "$projectDirectory" -c release --show-bin-path)"
appDirectory="$projectDirectory/build/Cargo.app"

mkdir -p "$appDirectory/Contents/MacOS"
cp "$binaryDirectory/Cargo" "$appDirectory/Contents/MacOS/Cargo"
cp "$projectDirectory/Resources/Cargo-Info.plist" "$appDirectory/Contents/Info.plist"
chmod +x "$appDirectory/Contents/MacOS/Cargo"

printf '%s\n' "$appDirectory"

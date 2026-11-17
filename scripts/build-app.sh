#!/bin/zsh
# Build Cargo.app and install it to /Applications, signed with the stable
# Apple Development identity from project.yml (so the Accessibility grant
# survives rebuilds). Regenerates the Xcode project and the icon every time.
#
#   ./scripts/build-app.sh            # Release → /Applications/Cargo.app
#   ./scripts/build-app.sh --debug
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
config=Release
[[ "${1:-}" == "--debug" ]] && config=Debug

cd "$here"
xcodegen generate --quiet
# HouseKit is the tag pinned in project.yml. Resolve it, then build
# housekit-icon from that same checkout. HOUSEKIT_PATH overrides it.
xcodebuild -resolvePackageDependencies -project Cargo.xcodeproj -scheme Cargo -derivedDataPath build/DerivedData -quiet >/dev/null
housekit="${HOUSEKIT_PATH:-$here/build/DerivedData/SourcePackages/checkouts/housekit}"
swift build -c release --package-path "$housekit" >/dev/null
"$(swift build -c release --package-path "$housekit" --show-bin-path)/housekit-icon" cargo "$here/Resources/AppIcon.icns" >/dev/null

{ read -r build; read -r commit; } < <(./scripts/build-number.sh)
xcodebuild -project Cargo.xcodeproj -scheme Cargo -configuration "$config" \
  -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build" CARGO_COMMIT="$commit" \
  CODE_SIGNING_ALLOWED=NO -quiet build
app="build/DerivedData/Build/Products/$config/Cargo.app"
# Xcode's Debug product is an executable shim that loads Cargo.debug.dylib at
# launch. Sign nested code first, otherwise the outer app can carry a stable
# Team ID while dyld rejects the debug dylib's linker/adhoc signature.
setopt null_glob
for nested in "$app/Contents/MacOS"/*.dylib "$app/Contents/Frameworks"/*.dylib; do
  [[ -e "$nested" ]] || continue
  codesign --force --sign "Apple Development" --options runtime "$nested"
done
codesign --force --sign "Apple Development" --entitlements Resources/Cargo.entitlements --options runtime "$app"

target=/Applications/Cargo.app
if pgrep -xq Cargo; then osascript -e 'tell application "Cargo" to quit' >/dev/null 2>&1 || true; sleep 0.5; fi
rm -rf "$target"
/usr/bin/ditto "$app" "$target"
codesign --verify --strict "$target"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")"
printf '%s (version %s, build %s, %s)\n' "$target" "$version" "$build" "$commit"

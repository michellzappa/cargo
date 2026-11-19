#!/bin/zsh
# Build Cargo.app and install it to ~/Applications by default, signed with the
# stable Apple Development identity from project.yml (so Keychain and TCC
# grants survive rebuilds). Use --system only when a /Applications install is
# explicitly wanted.
#
#   ./scripts/build-app.sh            # Release → ~/Applications/Cargo.app
#   ./scripts/build-app.sh --debug
#   ./scripts/build-app.sh --system   # Release → /Applications/Cargo.app
set -euo pipefail
here="$(cd "$(dirname "$0")/.." && pwd)"
housekit="${HOUSEKIT_PATH:-$here/../housekit}"
config=Release
installRoot="/Users/${USER}/Applications"
privilegedInstall=false
for argument in "$@"; do
  case "$argument" in
    --debug) config=Debug ;;
    --system)
      installRoot=/Applications
      privilegedInstall=true
      ;;
    *) print -u2 "Unknown option: $argument"; exit 2 ;;
  esac
done

swift build -c release --package-path "$housekit" >/dev/null
"$(swift build -c release --package-path "$housekit" --show-bin-path)/housekit-icon" cargo "$here/Resources/AppIcon.icns" >/dev/null

cd "$here"
xcodegen generate --quiet
{ read -r build; read -r commit; } < <(./scripts/build-number.sh)
xcodebuild -project Cargo.xcodeproj -scheme Cargo -configuration "$config" \
  -derivedDataPath build/DerivedData CURRENT_PROJECT_VERSION="$build" CARGO_COMMIT="$commit" \
  CODE_SIGNING_ALLOWED=NO -quiet build
app="build/DerivedData/Build/Products/$config/Cargo.app"
# Xcode's Debug product is an executable shim that loads Cargo.debug.dylib at
# launch. Sign nested code first, otherwise the outer app can carry a stable
# Team ID while dyld rejects the debug dylib's linker/adhoc signature.
# Two valid certificates can share the "Apple Development" name, and codesign
# refuses an ambiguous name. Sign by hash. Grants survive because the designated
# requirement names the certificate's common name, not its hash.
identity="${CARGO_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development:/ { print $2; exit }')}"
[[ -n "$identity" ]] || { print -u2 "No Apple Development signing identity found."; exit 1; }
setopt null_glob
for nested in "$app/Contents/MacOS"/*.dylib "$app/Contents/Frameworks"/*.dylib; do
  [[ -e "$nested" ]] || continue
  codesign --force --sign "$identity" --options runtime "$nested"
done
codesign --force --sign "$identity" --entitlements Resources/Cargo.entitlements --options runtime "$app"

target="$installRoot/Cargo.app"
if pgrep -xq Cargo; then osascript -e 'tell application "Cargo" to quit' >/dev/null 2>&1 || true; sleep 0.5; fi
if [[ "$privilegedInstall" == true ]]; then
  # This is intentionally the only privileged step: users who choose the
  # system-wide location authenticate once for the replacement, not at launch.
  sudo -v
  sudo rm -rf -- "$target"
  sudo /usr/bin/ditto "$app" "$target"
  sudo codesign --verify --strict "$target"
else
  mkdir -p "$installRoot"
  rm -rf -- "$target"
  /usr/bin/ditto "$app" "$target"
  codesign --verify --strict "$target"
fi
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$target/Contents/Info.plist")"
# Cargo's CLI runs inside the app binary so that it keeps the app's Keychain grants.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexec "%s/Contents/MacOS/Cargo" --cli "$@"\n' "$target" > "$HOME/.local/bin/cargoctl"
chmod +x "$HOME/.local/bin/cargoctl"
printf '%s (version %s, build %s, %s)\n' "$target" "$version" "$build" "$commit"

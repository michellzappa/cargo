# Cargo agent rules

Cargo is a native macOS resident app with an iOS companion. The resident owns
Put.io, Chill, metadata, the local library, and the authenticated remote API;
the iOS app is a remote client and must not receive resident credentials or
absolute local paths.

## Inspect the app with `cargoctl`

Use `cargoctl` to see what Cargo sees. Run `cargoctl help` for the commands. Do
not read `state.json` by hand or ask for tokens. `scripts/build-app.sh` installs
it to `~/.local/bin`. It runs inside the app binary (`Cargo --cli`) and keeps the
app's Keychain grants, so it needs no prompt and no token file. Cargo must run
for the resident commands. `local`, `putio` and `logs` work without it.

MCP clients use `cargo-mcp` (`Cargo --mcp`), a stdio MCP server that
`scripts/build-app.sh` installs next to `cargoctl`. Each tool runs a `cargoctl`
command through `CargoCLI.output(of:)`. Add a new capability to the CLI first,
then expose it as a tool in `CargoMCP.swift`.

## Preserve the worktree

- Treat existing uncommitted changes as user-owned. Inspect them before
  editing and do not reset, discard, or reformat unrelated files.
- Keep changes scoped to the request. Do not create commits or tags unless the
  user explicitly asks for them.
- Regenerate `Cargo.xcodeproj` with `xcodegen generate` after changing
  `project.yml`; the generated project is ignored and should not be hand-edited.

## Versioning

- The current macOS development version is `0.9.0`; the latest tagged macOS
  release is `v0.8.0`.
- The macOS marketing version is the `CFBundleShortVersionString` in
  `Resources/Info.plist`. Release tags must be exactly `vX.Y.Z` for that value.
- The iOS companion has its own marketing version in
  `Resources/CargoIOS-Info.plist`. Keep it independent until an iOS/App Store
  release needs a coordinated version.
- Use semantic versioning: patch for fixes, minor for compatible features,
  major for breaking product or data-contract changes. Do not bump the
  marketing version for every commit; bump it when preparing a release.

## Build numbers

- Never hand-edit `CFBundleVersion` for a normal build.
- `scripts/build-number.sh` derives the build from the Git commit count and
  returns the short commit as a second line. Local release builds and CI must
  pass both values as `CURRENT_PROJECT_VERSION` and `CARGO_COMMIT`.
- Every target that ships or is tested should use the same commit-derived build
  identity. About screens and health responses should make the version, build,
  and source commit visible.

## Changelog

- Keep user-visible work in `CHANGELOG.md` under `[Unreleased]` as it lands.
- Write entries by outcome, not by internal file or commit. Include notable
  features, behavior changes, fixes, safety changes, and migration concerns.
- When preparing a release, move `[Unreleased]` under a dated `X.Y.Z` heading,
  update the marketing version, verify the build workflow, and push the
  matching tag. Start a fresh `[Unreleased]` section immediately afterward.
- Keep the historical sections detailed enough to explain what a user got in
  each milestone between tags.

## About surfaces

- The macOS Settings About page uses HouseKit's `AboutPage`; keep the bundle
  metadata populated so it shows the current version and build.
- The iOS Settings page must include an About section showing version, build,
  and commit. Use the shared `CargoAppInfo` helper instead of duplicating
  `Bundle` parsing.

## Validation

For versioning or release changes, run at minimum:

```sh
xcodegen generate
./scripts/build-number.sh
plutil -lint Resources/Info.plist Resources/CargoIOS-Info.plist
zsh -n scripts/build-number.sh scripts/build-app.sh
xcodebuild build -project Cargo.xcodeproj -scheme Cargo \
  -configuration Debug CURRENT_PROJECT_VERSION=... CARGO_COMMIT=... \
  CODE_SIGNING_ALLOWED=NO
xcodebuild build -project Cargo.xcodeproj -scheme CargoIOS \
  -sdk iphonesimulator CURRENT_PROJECT_VERSION=... CARGO_COMMIT=... \
  CODE_SIGNING_ALLOWED=NO
```

Use the repository's existing sibling checkouts for `HouseKit` and `EasySubsKit`.

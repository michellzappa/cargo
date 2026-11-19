# Working on Cargo

Cargo moves media from Put.io to a local SSD library, with an IMDb watchlist,
TMDB metadata, subtitles and a remote API over Tailscale. AppKit, Swift 6,
macOS 14, bundle id `app.cargo.Cargo`. `PLAN.md` and `BUILD_ISSUES.md` hold
the design and the open risks.

## Build

XcodeGen owns the project. Edit `project.yml`, then run `xcodegen generate`.
`Cargo.xcodeproj` is not in git. Never hand-edit it.

- `./scripts/build-app.sh` regenerates the project and the icon, builds
  Release, signs with the stable Apple Development identity and installs to
  `~/Applications/Cargo.app` (`--system` for `/Applications`). `--debug`
  builds Debug. It also installs `cargoctl` and `cargo-mcp` to `~/.local/bin`.
  This is for mz's Mac.
- The green gate is the CI build (`.github/workflows/build.yml`):

```bash
xcodegen generate && xcodebuild build -project Cargo.xcodeproj -scheme Cargo -configuration Debug -derivedDataPath build/DerivedData CODE_SIGNING_ALLOWED=NO -quiet
```

Run it on mz-mini with `remote-build '<command>'` from inside the clone. Do
not build Swift on the laptop.

CI also runs `xcodebuild test` and a Release build. Release can fail where
Debug passes (`-O`, strict concurrency), so run both.

## Inspect and drive the app

Use `cargoctl` to see what Cargo sees. Run `cargoctl help` for the commands. Do
not read `state.json` by hand or ask for tokens. It runs inside the app binary
(`Cargo --cli`) and keeps the app's Keychain grants, so it needs no prompt and
no token file. Cargo must run for the resident commands. `local`, `putio` and
`logs` work without it.

MCP clients use `cargo-mcp` (`Cargo --mcp`), a stdio MCP server. Each tool runs
a `cargoctl` command through `CargoCLI.output(of:)`. Add a new capability to
the CLI first, then expose it as a tool in `CargoMCP.swift`.

## Shared package

HouseKit (`michellzappa/housekit`) supplies the menu bar plate, the app icon,
the status menu tail, the settings window, launch at login and the changelog
parser. `project.yml` pins a HouseKit release tag by URL (`exactVersion`), so
CI, mz-mini and the laptop build the same code.

- To change HouseKit: merge in its repo, tag a new release, then move the pin
  here on purpose. Never go back to `path: ../housekit`.
- `scripts/build-app.sh` builds `housekit-icon` from the resolved package
  checkout in `build/DerivedData`. Set `HOUSEKIT_PATH` to try a local
  HouseKit clone.
- EasySubsKit (`michellzappa/easysubs`) is still a path dependency
  (`../easysubs`). Clone it next to this repo. CI checks it out as a sibling.
- SwiftNIO is pinned by version in `project.yml` (the remote API server).

## Release

`.github/workflows/release.yml` runs on a `v*` tag. The tag must match
`CFBundleShortVersionString` in `Resources/Info.plist`. The workflow archives a
universal app, signs it with Developer ID, notarizes, staples and publishes a
zip plus `SHA256SUMS` to GitHub Releases.

- Add a `CHANGELOG.md` entry `## X.Y.Z - YYYY-MM-DD` before you tag. The app
  bundles the file for HouseKit's About pane.
- The workflow needs six secrets: `APPLE_TEAM_ID`,
  `APPLE_DEVELOPER_CERTIFICATE_P12_BASE64`, `APPLE_DEVELOPER_CERTIFICATE_PASSWORD`,
  `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID`, `APPLE_API_PRIVATE_KEY_BASE64`.

## Traps

- This repo has no Actions secrets. Every release run failed, so `v0.4.0`
  and `v0.8.0` are tags with no GitHub release.
- `scripts/build-number.sh` prints the build number (commit count) and the
  short SHA. The SHA ends in `-dirty` when the tree has changes.
- Debug builds load `Cargo.debug.dylib`. `build-app.sh` signs nested code
  first, else dyld rejects the dylib.
- The App Store Tailscale binary acts as a CLI only when `SHLVL` is set.
  Cargo sets it. Plain HTTP to a tailnet name needs the `ts.net` ATS
  exception in `Info.plist`.
- Deleting on Put.io cannot be undone. Keep remote deletion behind its
  setting and a confirmation.
- The Put.io token and the OpenSubtitles password live in the Keychain.
  Never write them to the JSON state file or to logs.
- Settings still uses the deprecated AppKit `SettingsWindowController` and
  `AboutPage`. They do not show the changelog.

## Writing

Docs, comments and commit messages use Simplified Technical English: active
voice, short sentences, one word for one thing. No em dashes in UI copy.

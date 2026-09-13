# Cargo

A native macOS menu-bar app that brings completed Put.io media home to a local
SSD library that Infuse reads. Quiet, local-first, no Sonarr/Radarr.

ShowRSS discovers and adds transfers to Put.io. Cargo owns the handoff:

```text
Put.io transfers → completed Put.io files → hidden _Inbox on the SSD
        ↓
identify movie / episode / ambiguous
        ↓
Movies/Title (Year).mkv  ·  TV Shows/Show (Year)/Season 02/Show (Year) - S02E01.mkv
```

The product principle: **make it obvious what is happening in Put.io, and make
bringing media home safe and repeatable.** Nothing is deleted remotely until a
local copy is verified, and ambiguous files wait in `_Inbox` for a human.

## How it works

The menu bar item shows live status (account, transfers, Inbox count) and the
actions: Open Cargo ⌘O, Add Transfer… ⌘N, Refresh ⌘R. The dashboard window has
a sidebar — Transfers, Files, Inbox, Watchlist, History — each a native table.

Every `refreshIntervalMinutes` the background cycle:

1. refreshes Put.io transfers and the recursive video inventory,
2. downloads newly completed video media into `_Inbox` (staging, resumable),
3. classifies and renames Inbox media into the Movies / TV Shows layout,
4. optionally deletes the Put.io original after the local copy verifies,
5. removes sidecars and empty folders, and posts one notification.

Each step is a switch in Settings → Automation. The Watchlist page follows a
public IMDb Watchlist as a *desired* list (Wanted → Available → Queued →
Downloaded → Organized); availability stays with ShowRSS and Put.io.

## Requirements

- macOS 14 (Sonoma) or later
- A Put.io account. Cargo authorizes in the browser through its registered OAuth
  app and the `cargo://oauth/callback` scheme; the token lives in Keychain.
- A folder for the library. Cargo keeps a security-scoped bookmark to it and
  never rearranges what is already there.

## Install

No notarized release yet. Build it yourself:

```sh
./scripts/build-app.sh      # → /Applications/Cargo.app, signed, icon regenerated
```

Needs `xcodegen` and the sibling [`../housekit`](../housekit) package, which
supplies the menu bar plate, the app icon, the settings window chrome and
launch-at-login — the pieces Cargo shares with Tessellate and Strata. To work
in Xcode instead: `xcodegen generate && open Cargo.xcodeproj`. Tests:

```sh
xcodebuild test -project Cargo.xcodeproj -scheme Cargo CODE_SIGNING_ALLOWED=NO
```

### A note on signing

`project.yml` signs with a stable Apple Development identity, not ad-hoc.
Keychain and TCC key their grants to the code signature, so an ad-hoc build
would lose the Put.io token and the folder bookmark on every rebuild. Set your
own `DEVELOPMENT_TEAM` in `project.yml`.

## Configuration

Settings lives in the menu bar item (⌘,): **Put.io** (account, polling
interval) · **Library** (library folder, folder names, IMDb watchlist) ·
**Automation** (each background step, notifications) · **General** (launch at
login) · **About**.

## Architecture

AppKit throughout, no dependencies beyond `HouseKit`.

| | |
| --- | --- |
| `Services/PutIOClient`, `PutIOOAuth`, `KeychainStore` | Put.io API, browser OAuth, token storage |
| `Services/CargoCoordinator` | The state machine: background cycle, sync jobs, settings mutations |
| `Services/LibraryOrganizer` | Release-name parsing, destination preview, atomic move |
| `Services/IMDbWatchlistService` | Public watchlist fetch and pagination |
| `Core/CargoStore` | One JSON state file in Application Support, durable job history |
| `UI/MainWindowController`, `Pages`, `ListTableViewController` | Dashboard: sidebar + native tables |
| `UI/SettingsPages` | The HouseKit settings window with Cargo's pages |
| `CargoApp` | `NSStatusItem` and its menu — header, actions, then the house tail |

See [PLAN.md](PLAN.md) for milestones and [BUILD_ISSUES.md](BUILD_ISSUES.md)
for known risks.

## Limitations

- Downloads are not yet resumable across sleep or SSD removal.
- Media identification is heuristic; low-confidence files stay in `_Inbox`.
- Remote deletion is off by default and stays a separate switch.
- No ShowRSS parsing or magnet submission — that is upstream, on purpose.

# Cargo

A native macOS menu-bar app that brings completed [Put.io](https://put.io)
media home to a local SSD library that [Infuse](https://firecore.com/infuse)
reads. Quiet, local-first, no Sonarr/Radarr, no server to run.

```text
Chill / IMDb watchlist / a pasted link
        ↓
Put.io transfer  →  completed file  →  _Inbox on the SSD (resumable download)
        ↓
identify movie / episode / ambiguous
        ↓
Movies/Title (Year).mkv
TV Shows/Show (Year)/Season 02/Show (Year) - S02E01.mkv   (+ Title (Year).srt)
        ↓
Put.io copy deleted — only after the local copy is verified
```

The principle: **make it obvious what is happening in Put.io, and make bringing
media home safe and repeatable.** Nothing is deleted remotely until a local copy
is verified byte-for-byte, ambiguous files wait in `_Inbox` for a human, and the
app never rearranges what is already in the library.

## What it does

Cargo lives in the menu bar. The item shows live status (account, transfers,
Inbox count) and the actions: Open Cargo ⌘O, Add Transfer… ⌘N, Refresh ⌘R.
Opening the dashboard gives Cargo a normal window and Dock icon; ⌘Q closes
the windows and leaves the background service running. Quit is in the
menu-bar menu.

Every minute (configurable) the background cycle:

1. refreshes the Put.io account, transfers and activity feed, mirroring
   completed and failed transfers into History,
2. walks the video inventory when something landed — folders are listed with a
   server-side type filter so sidecars never cross the wire,
3. asks Put.io to unpack any archive it finds and removes the archive once
   the videos inside exist,
4. downloads newly completed video into `_Inbox` — streamed into a `.part`
   file, resumed from it after sleep, network loss or a restart,
5. classifies and renames Inbox media into the Movies / TV Shows layout,
6. deletes the Put.io original after the local copy verifies, skipping the
   trash so the quota is actually freed,
7. fetches a subtitle for what it organized — Put.io's own if it had one,
   else OpenSubtitles through [EasySubsKit](https://github.com/michellzappa/easysubs)
   (hash match, then filename),
8. removes sidecars and empty folders, and posts one notification.

Each step is a switch in Settings → Automation.

### The dashboard

| Page | What it is |
| --- | --- |
| **Discover** | Chill Institute release search plus its top movies and series. Selecting a title searches releases with its year; “Send to Put.io” is explicit. |
| **Transfers** | Put.io transfers with progress; add, cancel, retry, clean finished. |
| **Files** | Put.io's file tree. Queue a download, request extraction, delete (to trash). |
| **Inbox** | The `_Inbox` staging folder: downloads with live progress, the proposed destination, Organize. |
| **Library** | The SSD itself, rescanned each cycle. With a TMDB key: posters, completeness (*Season 2 · 7 of 10*), Find on Put.io for missing episodes. Tabs: All · Movies · TV Shows · Incomplete · Unmatched. Reveal in Finder, Play in Infuse, Open on TMDB, Move to Trash. |
| **Watchlist** | A public IMDb Watchlist followed as a *desired* list: Wanted → Available → Queued → Downloaded → Organized. |
| **History** | What the cycle did, and what needs attention. |

⌘K searches the cached Library and Watchlist by title, year, path or IMDb id
and can hand the query to Discover.

### A second Mac

One Cargo owns the SSD and Put.io (the *resident*); any other Mac runs the
same app as a *client* and gets the same dashboard, driven over an
authenticated HTTP API. On the resident: Settings → Remote Access →
**Copy pairing link**. That switches the API to local-network scope and copies
one `cargo://pair?url=…&token=…` string, using the Mac's Tailscale MagicDNS
name when Tailscale is running. On the client, paste it into *Resident
address* and Connect — or just open the link.

The client sees the resident's state (refreshed every 15 s) and sends actions
back: transfers, downloads, organize, delete, watchlist refresh. Discover search
is the client's own. Put.io, Chill and TMDB credentials, the SSD bookmark and
local paths never leave the resident; the client only holds the bearer token,
in Keychain. Loopback is the default scope; local-network scope should sit
behind the Mac firewall or a tailnet, and the token can be rotated at any time.

## Requirements

- macOS 14 (Sonoma) or later
- A Put.io account. Cargo authorizes in the browser through its registered
  OAuth app and the `cargo://oauth/callback` scheme; the token lives in Keychain.
- An SSD (or any folder) for the library. Cargo keeps a security-scoped
  bookmark to it.
- Optional: a [Chill Institute](https://chill.institute) token for Discover,
  a TMDB API key for posters and completeness, an OpenSubtitles account for
  subtitles, a public IMDb Watchlist URL. All tokens live in Keychain.

## Install

Tagged releases ship a notarized zip through GitHub Releases. To build it
yourself:

```sh
./scripts/build-app.sh      # → /Applications/Cargo.app, signed, icon regenerated
```

Needs `xcodegen` and two sibling checkouts next to this repo:
[`../housekit`](https://github.com/michellzappa/housekit) (menu-bar plate, app
icon, settings window chrome, launch-at-login — shared with the author's other
Mac apps) and [`../easysubs`](https://github.com/michellzappa/easysubs)
(subtitles). To work in Xcode: `xcodegen generate && open Cargo.xcodeproj`.

```sh
xcodebuild test -project Cargo.xcodeproj -scheme Cargo CODE_SIGNING_ALLOWED=NO
```

`project.yml` signs with a stable Apple Development identity rather than
ad-hoc: Keychain and TCC key their grants to the code signature, so an ad-hoc
build would lose the Put.io token and the folder bookmark on every rebuild.
Set your own `DEVELOPMENT_TEAM` there.

## Settings

⌘, from the menu bar. **Put.io** (account, disk usage, trash, polling
interval) · **Chill** (token) · **Library** (folder, folder names, TMDB key,
OpenSubtitles, IMDb watchlist) · **Automation** (each background step,
notifications) · **Remote Access** (API scope, token, pairing, connect as a
client) · **General** (launch at login) · **About**.

State is one JSON file in `~/Library/Application Support/Cargo/`; the previous
version is kept as `state.json.bak`, and an undecodable one is set aside as
`state.json.corrupt` rather than overwritten.

## Architecture

AppKit throughout, Swift 6 strict concurrency, no storyboards. Dependencies:
`HouseKit`, `EasySubsKit`, SwiftNIO (for the API server).

| | |
| --- | --- |
| `CargoApp` | `NSStatusItem`, menus, URL scheme (`oauth`, `pair`, `open`), background cycle timer, API server lifecycle |
| `Services/CargoCoordinator` | The state machine: background cycle, sync jobs, settings mutations, client-mode proxying |
| `Services/PutIOClient`, `PutIOOAuth`, `KeychainStore` | Put.io API (account, transfers, files, resumable download, delete/skip-trash, events, extract, trash), browser OAuth, token storage |
| `Services/ChillClient` | Chill catalogs, search, episode lookup, explicit Put.io handoff |
| `Services/LibraryOrganizer` | Release-name parsing, destination preview, atomic move |
| `Services/LibraryIndex`, `TMDBClient`, `OMDBClient` | Disk scan of the library layout; TMDB find/search/season counts, poster cache; OMDb ratings |
| `Services/IMDbWatchlistService` | Public watchlist fetch and pagination |
| `Services/SubtitleService` | Put.io subtitle parking + OpenSubtitles via `EasySubsKit` |
| `Core/CargoStore` | The JSON state file, with backup and corrupt-file preservation |
| `Core/CargoRemoteControl` | Remote-safe read models, transport-neutral commands, presence registry |
| `Services/CargoRemoteAPI`, `CargoHTTPServer` | HTTP API v1 (bearer token, constant-time compare), discovery, Tailscale peer auto-find, client session |
| `UI/*` | Dashboard window, pages, tables, poster grid, ⌘K search, settings pages |

### HTTP API

`http://127.0.0.1:39817` by default (`0.0.0.0` in local-network scope). Every
route except `/v1/discovery` needs `Authorization: Bearer <token>`.

```text
GET  /v1/health
GET  /v1/discovery                 (unauthenticated: name, instance id, port)
GET  /v1/state                     full remote-safe snapshot
GET  /v1/transfers | /v1/files | /v1/inbox | /v1/library | /v1/watchlist
GET  /v1/events?since=<revision>   change feed; snapshot included when changed
GET  /v1/presence
POST /v1/presence/register | /heartbeat | /unregister
GET  /v1/discover/catalog
POST /v1/discover/search           {"query":"The Bear 2024"}   (stateless)
POST /v1/commands                  {"type":"refresh"}
```

Commands: `refresh`, `refreshChillCatalog`, `sendChillRelease`,
`sendChillMovie`, `addTransfer`, `cancelTransfer`, `retryTransfer`,
`cleanFinishedTransfers`, `requestExtraction`, `deleteRemoteFile`,
`enqueueLocalSync`, `organizeLocalJob`, `refreshWatchlist`, `clearFailedJobs`,
`clearHistory`.

See [PLAN.md](PLAN.md) for milestones and [BUILD_ISSUES.md](BUILD_ISSUES.md)
for the working notes on risks — both are the author's ledgers rather than
polished docs.

## License

MIT — see [LICENSE](LICENSE).

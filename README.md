# Cargo

A native macOS menu-bar app that brings completed Put.io media home to a local
SSD library that Infuse reads. Quiet, local-first, no Sonarr/Radarr.

Chill Institute discovers releases; Cargo sends the selected link to Put.io and
owns the handoff:

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
actions: Open Cargo ⌘O, Add Transfer… ⌘N, Refresh ⌘R. Opening the dashboard
gives Cargo a normal window and Dock icon. ⌘Q closes the app windows and leaves
the background service running in the menu bar; choose Quit Cargo from the
menu-bar menu to terminate it. The dashboard window has
a sidebar — Discover, Transfers, Files, Inbox, Library, Watchlist, History —
each a native table. Discover searches Chill and offers an explicit “Send to
Put.io” action; it also shows Chill's top movies and series as browsable lists,
where selecting a title searches releases with its year. Put.io remains the file
manager and Cargo's download source.

Press ⌘K (Edit → Search Cargo…) to search the cached Library and Watchlist by
title, year, path, or IMDb id. The same palette can hand the query to Discover;
selecting a Library result opens its detail view and a Watchlist result opens its
IMDb permalink.

**Library** is the SSD itself, rescanned every cycle from the folder layout
the organizer writes: Movies and TV Shows with seasons, episode counts, size
and date added. With a TMDB API key (Settings → Library, free for personal
use, kept in Keychain) rows get posters and shows get completeness — *Season 2
· 7 of 10* — and Watchlist entries link to library items by TMDB id instead of
title guessing. Tabs: All · Movies · TV Shows · Incomplete · Unmatched (no TMDB match yet — rename the folder, then Search on IMDb / Retry Misses).
An incomplete show's "Find on Put.io" searches the account (`files/search`)
and queues any missing episode it finds. Discover is the complementary Chill
release search; it does not manage indexers or remote files. Reveal in Finder,
Play in Infuse, Open on TMDB, Move to Trash.

Every `refreshIntervalMinutes` the background cycle:

1. refreshes the account, transfers and Put.io's activity feed (`events/list`),
   mirroring completed and failed transfers into History,
2. walks the video inventory — only when something landed, an extraction is
   in flight, or every tenth cycle; folders are listed with a server-side
   `file_type` filter so sidecars never cross the wire,
3. asks Put.io to unpack any archive it finds (rar'd releases) and removes the
   archive once the videos inside exist,
4. downloads newly completed video media into `_Inbox` (staging, resumable),
5. classifies and renames Inbox media into the Movies / TV Shows layout,
6. deletes the Put.io original after the local copy verifies — skipping the
   trash, so the quota is actually freed,
7. fetches a subtitle for what it organized — Put.io's own if it had one
   (saved before the remote copy is deleted), else OpenSubtitles through
   [EasySubsKit](https://github.com/michellzappa/easysubs) (hash match, then
   filename) — as `Title (Year).srt` beside the video,
8. removes sidecars and empty folders, and posts one notification.

Settings → Put.io shows disk usage and what is in the trash, with Empty Trash
for the files you deleted by hand (those do go to the trash, on purpose).

Each step is a switch in Settings → Automation. The Watchlist page follows a
public IMDb Watchlist as a *desired* list (Wanted → Available → Queued →
Downloaded → Organized). “Search in Cargo” opens Discover with the title and
IMDb year when available, which helps Chill resolve the actual release title;
Put.io remains responsible for transfers and files.

## Requirements

- macOS 14 (Sonoma) or later
- A Put.io account. Cargo authorizes in the browser through its registered OAuth
  app and the `cargo://oauth/callback` scheme; the token lives in Keychain.
- A Chill Institute account/token for the optional Discover page. The token
  lives in Keychain and can be revoked independently.
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
interval) · **Chill** (release discovery token) · **Library** (library folder, folder names, IMDb watchlist) ·
**Automation** (each background step, notifications) · **General** (launch at
login) · **About**. Settings → Library also holds the TMDB key and the
OpenSubtitles account + language for subtitles.

## Architecture

AppKit throughout; dependencies are the sibling packages `HouseKit` and `EasySubsKit`.

| | |
| --- | --- |
| `Services/PutIOClient`, `PutIOOAuth`, `KeychainStore` | Put.io API (account, transfers, files with type filter, download, delete/skip-trash, events, extract, trash), browser OAuth, token storage |
| `Services/ChillClient` | Native Connect/JSON client for Chill catalogs, search, profile verification, episode lookup, and explicit Put.io handoff |
| `Services/CargoCoordinator` | The state machine: background cycle, sync jobs, settings mutations |
| `Services/LibraryOrganizer` | Release-name parsing, destination preview, atomic move |
| `Services/IMDbWatchlistService` | Public watchlist fetch and pagination |
| `Services/LibraryIndex`, `TMDBClient` | Disk scan of the library layout; TMDB find/search/season counts, poster cache |
| `Services/SubtitleService` | Put.io subtitle parking + OpenSubtitles via `EasySubsKit` (sibling package `../easysubs`) |
| `Core/CargoStore` | One JSON state file in Application Support, durable job history |
| `Core/CargoRemoteControl` | Remote-safe read models, transport-neutral commands, and same-app client/resident control |
| `Services/CargoRemoteAPI`, `CargoHTTPServer` | Authenticated HTTP API v1 plus low-information discovery, backed by SwiftNIO |
| `UI/MainWindowController`, `Pages`, `ListTableViewController` | Dashboard: sidebar + native tables |
| `UI/SettingsPages` | The HouseKit settings window with Cargo's pages |
| `CargoApp` | `NSStatusItem` and its menu — header, actions, then the house tail |

See [PLAN.md](PLAN.md) for milestones and [BUILD_ISSUES.md](BUILD_ISSUES.md)
for known risks.

The remote-control boundary is intentionally resident-first: it exposes
remote-safe Put.io/Chill/library/watchlist/history state and explicit commands,
while keeping provider Keychain tokens, security-scoped bookmarks, absolute
local paths, and AppKit actions inside the resident Cargo process. A connected
client renders the same dashboard from the resident snapshot and sends
supported actions back to the resident; it does not need its own Put.io, Chill,
TMDB, OMDb, or subtitle credentials. Remote Access keeps the listener
loopback-only by default, offers an explicit local-network scope, supports
Tailscale peer auto-find, and can rotate the bearer token stored in Keychain.

### Local API preview

Cargo 0.8.0 starts an authenticated API on `127.0.0.1:39817` by default. It
requires the bearer token stored in the macOS Keychain and supports state,
transfers, files, Inbox, library, watchlist, Chill catalog, Chill search, and
explicit remote commands:

```text
GET  /v1/health
GET  /v1/discovery                 (unauthenticated, low-information)
GET  /v1/state
GET  /v1/transfers
GET  /v1/files
GET  /v1/inbox
GET  /v1/library
GET  /v1/watchlist
GET  /v1/events?since=12
GET  /v1/presence
POST /v1/presence/register
POST /v1/presence/heartbeat
POST /v1/presence/unregister
GET  /v1/discover/catalog
POST /v1/discover/search   {"query":"The Bear 2024"}
POST /v1/commands          {"type":"refresh"}
```

The `/v1/commands` body is a `CargoRemoteCommand` such as `refresh`,
`addTransfer`, `cancelTransfer`, `retryTransfer`, `cleanFinishedTransfers`,
`requestExtraction`, `deleteRemoteFile`, `enqueueLocalSync`,
`refreshWatchlist`, `clearFailedJobs`, or `clearHistory`. The token can be
copied or rotated from Settings → Remote Access. The intended remote
experience is another instance of the same Cargo app: one Cargo acts as the
resident server and any number of trusted Cargo installations act as clients.
The client dashboard consumes the revisioned event feed by polling. Local
filesystem-only actions, such as Finder reveals and library rescans, remain
resident-only.

## Limitations

- Downloads are not yet resumable across sleep or SSD removal.
- Media identification is heuristic; low-confidence files stay in `_Inbox`.
- Remote deletion is off by default and stays a separate switch.
- No indexer management or torrent discovery logic — Chill is the discovery provider; Put.io remains the file manager.

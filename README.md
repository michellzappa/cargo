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
actions: Open Cargo ⌘O, Add Transfer… ⌘N, Refresh ⌘R. The dashboard window has
a sidebar — Discover, Transfers, Files, Inbox, Library, Watchlist, History —
each a native table. Discover searches Chill and offers an explicit “Send to
Put.io” action; it also shows Chill's top movies and series as browsable lists,
where selecting a title searches releases with its year. Put.io remains the file
manager and Cargo's download source.

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
| `Core/CargoRemoteControl` | Remote-safe read models and transport-neutral commands for a future resident API |
| `UI/MainWindowController`, `Pages`, `ListTableViewController` | Dashboard: sidebar + native tables |
| `UI/SettingsPages` | The HouseKit settings window with Cargo's pages |
| `CargoApp` | `NSStatusItem` and its menu — header, actions, then the house tail |

See [PLAN.md](PLAN.md) for milestones and [BUILD_ISSUES.md](BUILD_ISSUES.md)
for known risks.

The remote-control boundary is intentionally local-first: it exposes cached
Put.io/Chill/library/watchlist/history state and explicit commands, while
keeping Keychain tokens, security-scoped bookmarks, absolute local paths, and
AppKit inside the resident Cargo process. The network listener and remote
client are separate follow-up milestones.

## Limitations

- Downloads are not yet resumable across sleep or SSD removal.
- Media identification is heuristic; low-confidence files stay in `_Inbox`.
- Remote deletion is off by default and stays a separate switch.
- No indexer management or torrent discovery logic — Chill is the discovery provider; Put.io remains the file manager.

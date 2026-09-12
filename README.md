# Cargo

Cargo is a native macOS menu-bar app for managing a personal media pipeline built around Put.io and a local SSD library.

ShowRSS remains responsible for discovery and adding transfers to Put.io. Cargo is responsible for the handoff:

```text
Put.io transfers → completed Put.io files → local SSD staging → organized Infuse library
```

The project is intentionally independent of Sonarr and Radarr. It is a focused Put.io control plane with a local, durable job history.

## Current status

The first vertical slice is in place:

- native `NSStatusItem` menu-bar app
- normal dashboard window opened from the menu bar or its context menu
- native macOS sidebar navigation for Transfers, Files, Inbox, Watchlist, History, and Settings
- persisted local state store
- remote transfer and local sync job models
- browser-only Put.io OAuth with the access token stored in macOS Keychain
- read-only Put.io account and transfer refresh
- recursive Put.io media inventory across all folders
- remote media paths and idempotent local-sync queueing
- dynamic public IMDb Watchlist sync with Put.io comparison
- video-only tracking for Put.io files and local Inbox items
- SSD library-root selection with a persisted security-scoped bookmark
- first local handoff into a hidden SSD staging directory
- background workflow cycles for newly completed Put.io media
- durable workflow history and meaningful macOS notifications
- native launch-at-login support
- build and test target
- documented implementation plan and known risks

Cargo now has an explicit Inbox organization step: it classifies media, previews the destination, removes common release metadata from the filename, and moves the file into the configured Movies or TV Shows layout.

The Automation section controls each background step independently. Cargo establishes a baseline on its first background pass, then scans every Put.io folder and can sync only newly discovered video media, organize and rename the resulting Inbox media, send notifications, and launch at login. A failed or conflicting organization remains in `_Inbox` and is recorded in History.

### Browser authentication setup

Cargo uses one registered Put.io OAuth app (`9732`) and the native `cargo://oauth/callback` URL scheme. Choose “Connect with Put.io”; the browser authorization returns an access token that Cargo stores in macOS Keychain. There is intentionally no manual-token path in the UI.

### Local library workflow

Cargo treats the folder selected in “Local library” as the existing root that Infuse reads. It does not currently scan or rearrange that folder, and it never assumes that an empty new library should replace an existing one.

The Files view is a recursive inventory of video files in Put.io, not just the current root folder. Each row shows its Put.io path and whether Cargo has not downloaded it, has placed it in `_Inbox`, or has organized it into the library. Cargo ignores non-media sidecars and folders for syncing.

The Watchlist view loads the configured public IMDb Watchlist through IMDb’s public list data endpoint, resolving both the shared `p.…` profile URL and the older `ur…` user URL without storing IMDb credentials. Cargo keeps the IMDb IDs, titles, and added dates locally, follows pagination, shows newest-added titles first, refreshes automatically at most every 15 minutes, and labels each title as Wanted, Available in Put.io, Queued, Downloaded in Inbox, or Organized. The watchlist is a desired list only; ShowRSS and Put.io remain the availability pipeline.

The intended handoff is:

```text
Put.io completed file
        ↓
hidden _Inbox staging folder
        ↓
identify movie / episode / ambiguous file
        ↓
preview destination using the existing Movies and TV Shows folders
        ↓
move into the library, then run EasySubs
```

The current build has a focused Inbox view that recursively scans the physical `_Inbox` folder and can immediately move a confidently classified item. Cargo tracks video media only: non-video files such as subtitles, artwork, metadata, archives, and hidden macOS files are ignored for media tracking. Put.io folders remain visible for navigation, but only video files can be queued. After a nested Inbox folder has no media or subfolders left, the enabled cleanup step removes its remaining sidecars/cruft and the folder, while never removing `_Inbox` itself. On organize, Cargo cleans common release metadata: movies become names such as `Jodorowsky's Dune (2013).mkv`, while TV episodes become names such as `Adults (2025) - S02E01.mkv` inside `TV Shows/Adults (2025)/Season 02/`. The original downloaded filename remains visible in Inbox and the final path is shown after the move. A verified local copy can also trigger removal of the matching Put.io file and any now-empty parent folders. Ambiguous names, duplicates, and unsupported video files should be reviewed instead of being guessed or moved automatically. “In inbox · awaiting organization” means the download succeeded and the file is still safely sitting in `_Inbox`; it is not an error.

To build a launchable app bundle locally:

```sh
./Scripts/build-app.sh
open /Users/mz/Applications/Cargo.app
```

Cargo currently uses version `0.3.0` for the alpha product line. The packaging script derives `CFBundleVersion` from the current git commit count, so each committed build receives a reproducible increasing build number.

## Build

```sh
swift build
swift test
```

The executable can be run directly from the build directory, although a proper signed `.app` bundle is the supported launch path.

## Product boundary

Cargo does not currently discover releases, parse ShowRSS feeds, or submit magnets. Those responsibilities stay upstream in ShowRSS and Put.io. Cargo can observe a public IMDb Watchlist as a desired list, then watches Put.io for matching media and manages the local library handoff.

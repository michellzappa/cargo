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
- normal dashboard window opened from the menu bar
- persisted local state store
- remote transfer and local sync job models
- browser-only Put.io OAuth with the access token stored in macOS Keychain
- read-only Put.io account and transfer refresh
- remote root file browsing with idempotent local-sync queueing
- remote-folder navigation from the menu-bar dashboard
- SSD library-root selection with a persisted security-scoped bookmark
- first local handoff into a hidden SSD staging directory
- periodic Put.io refresh while Cargo is running
- build and test target
- documented implementation plan and known risks

Library organization is the next implementation step after the staging handoff.

### Browser authentication setup

Cargo uses one registered Put.io OAuth app (`9732`) and the native `cargo://oauth/callback` URL scheme. Choose “Connect with Put.io”; the browser authorization returns an access token that Cargo stores in macOS Keychain. There is intentionally no manual-token path in the UI.

### Local library workflow

Cargo treats the folder selected in “Local library” as the existing root that Infuse reads. It does not currently scan or rearrange that folder, and it never assumes that an empty new library should replace an existing one.

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

The current build shows a “Local inbox” preview and can explicitly move a confidently classified item. It keeps the downloaded filename for now and proposes a destination based on a conservative filename check: `S01E02`-style names become TV episodes under `TV Shows/<show>/Season 01/`, recognized standalone video files become movie candidates, and ambiguous files go to review. The folder names shown in Settings are destination names inside the selected root, so the next organization slice should first inspect and respect the folders already present there. Ambiguous names, duplicates, and unsupported files should be reviewed instead of being guessed or moved automatically. “In inbox · awaiting organization” means the download succeeded and the file is still safely sitting in `_Inbox`; it is not an error.

To build a launchable app bundle locally:

```sh
./Scripts/build-app.sh
open /Users/mz/Applications/Cargo.app
```

Cargo currently uses version `0.1.0` for the alpha product line. The packaging script derives `CFBundleVersion` from the current git commit count, so each committed build receives a reproducible increasing build number.

## Build

```sh
swift build
swift test
```

The executable can be run directly from the build directory, although a proper `.app` bundle and login item will be added before distribution.

## Product boundary

Cargo does not currently discover releases, parse ShowRSS feeds, or submit magnets. Those responsibilities stay upstream in ShowRSS and Put.io. Cargo observes the resulting Put.io state and manages the local library handoff.

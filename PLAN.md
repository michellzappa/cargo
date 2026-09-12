# Cargo plan

## Product definition

Cargo is a quiet, local-first Put.io manager for a Mac that has a removable media SSD shared to Infuse on Apple TV.

The core promise is: **make it obvious what is happening in Put.io, and make bringing completed media home safe and repeatable.**

## Milestones

### 0. Native shell — current

- [x] Create a macOS Swift Package executable.
- [x] Add an AppKit status-item application.
- [x] Add a normal dashboard window opened from the menu bar with remote and local queues.
- [x] Add a durable local state model.
- [x] Add unit-test scaffolding.
- [x] Make Settings mirror the media workflow step by step.
- [x] Separate Transfers, Files, Inbox, History, and Settings into focused main-window views.
- [x] Add reproducible app version and build-number packaging.

### 1. Put.io read-only integration

- [x] Add browser-only OAuth sign-in using the registered Cargo app (`9732`).
- [x] Fetch account information and remote transfers.
- [x] Add browser OAuth sign-in with state validation.
- [x] Fetch remote files and navigate Put.io folders.
- [x] Limit Cargo tracking to video media files while retaining folders for navigation.
- [x] Map Put.io statuses into Cargo statuses.
- [ ] Add refresh, retry, cancel, and open-in-browser actions.
- [ ] Keep the app useful when Put.io is unavailable by showing cached state and a stale indicator.
- [x] Poll Put.io on a basic fixed interval and update the open dashboard.

### 2. Local sync pipeline

- [x] Let the user choose and authorize the SSD library root.
- [x] Persist a security-scoped bookmark for the selected volume.
- [x] Add the first local download job execution path.
- [x] Download selected remote files into a hidden staging directory.
- [ ] Add progress, pause, resume, retry, and cancellation.
- [ ] Verify size and/or checksum before import.
- [ ] Resume safely after app restart, SSD removal, or network failure.

### 3. Library organization

- [x] Store configurable staging, Movies, and TV Shows folder names.
- [ ] Treat the selected SSD folder as the existing Infuse library root; do not reorganize existing content automatically.
- [ ] Inspect the existing root and learn/confirm its current Movies and TV Shows folders.
- [x] Identify common movie and episode filename patterns, using the filename as the initial signal.
- [x] Show a proposed destination from the configured library layout before moving anything.
- [x] Recursively scan the physical `_Inbox` folder so nested, manually placed, or previously untracked files are visible.
- [x] Ignore non-video Inbox files and sidecars such as subtitles, artwork, metadata, and archives.
- [x] Remove empty nested Inbox folders after their final file is organized, while preserving `_Inbox` itself.
- [x] Apply conservative movie and TV episode rename rules during explicit Inbox organization.
- [ ] Confirm finer rename and reorganization rules with the existing Infuse folder layout.
- [x] Move verified files from hidden `_Inbox` into the chosen existing destination after an explicit Organize action.
- [ ] Quarantine ambiguous or unsupported files instead of guessing.
- [ ] Detect duplicates and existing library files before import.
- [ ] Add optional remote cleanup only after verified local import and explicit confirmation.

### 4. Background operation

- [x] Add launch-at-login with the native macOS login-item service.
- [x] Add transfer-aware background polling for newly completed media.
- [ ] Watch the SSD mount/unmount state.
- [x] Send meaningful macOS notifications for workflow changes.
- [x] Add a history view for completed, organized, and failed jobs.

### 5. EasySubs integration

- [ ] Confirm the integration contract for EasySubs.
- [ ] Prefer a local protocol or file-based handoff over app-specific coupling.
- [ ] Add subtitle processing as a post-import job type.
- [ ] Keep subtitle failures independent from media import success.

### 6. Optional metadata/watchlist features

- [ ] Import IMDb Watchlist CSV as a read-only desired list.
- [ ] Show release/availability metadata without making it a downloader.
- [ ] Add other list providers only if they solve a real workflow gap.

## Non-goals for the first release

- indexer management
- torrent/magnet discovery
- replacing ShowRSS
- Plex/Jellyfin server management
- transcoding
- multi-user access
- cloud backend or account system

## Design principles

1. Local-first: credentials, state, and history stay on the Mac.
2. Idempotent: polling the same Put.io data never creates duplicate local jobs.
3. Explainable: every job shows why it is waiting, blocked, skipped, or failed.
4. Conservative: ambiguous media is quarantined for review.
5. Recoverable: never delete remote or local content without an explicit policy and a verified prior step.

## Local library sorting decision

Sorting is a workflow stage after download, not part of the Put.io transfer view. Cargo should use the selected SSD folder as the source of truth for the existing Infuse library:

1. Download the completed Put.io file into hidden `_Inbox` staging.
2. Inspect the filename and Put.io folder context.
3. Classify it as a movie, TV episode/season, or ambiguous item.
4. Preview the exact destination using the existing Movies and TV Shows folders.
5. Move only after the proposed destination is accepted or the rule is trusted.
6. Run EasySubs after a successful import.
7. Offer remote deletion only after local verification and explicit confirmation.

Cargo should not create a second library layout or reorganize files that were already on the SSD. Existing folder names and structure are therefore inputs to the organizer, while the Settings folder names remain the initial explicit destination configuration.

## Settings information architecture

Settings is deliberately a workflow, not a flat list of unrelated preferences:

1. Connect Put.io in the browser.
2. Observe remote transfers.
3. Sync completed files to hidden SSD staging.
4. Classify, preview, and organize into the existing local library.
5. Run post-import automation such as EasySubs.
6. Notify on meaningful changes.

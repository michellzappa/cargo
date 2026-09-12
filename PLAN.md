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
- [x] Add reproducible app version and build-number packaging.

### 1. Put.io read-only integration

- [x] Add browser-only OAuth sign-in using the registered Cargo app (`9732`).
- [x] Fetch account information and remote transfers.
- [x] Add browser OAuth sign-in with state validation.
- [x] Fetch remote files and navigate Put.io folders.
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
- [ ] Identify common movie and episode filename patterns, using Put.io folder context as a signal.
- [ ] Create a proposed destination from the existing library layout and show it before moving anything.
- [ ] Move verified files atomically from hidden staging into the chosen existing destination.
- [ ] Quarantine ambiguous or unsupported files instead of guessing.
- [ ] Detect duplicates and existing library files before import.
- [ ] Add optional remote cleanup only after verified local import and explicit confirmation.

### 4. Background operation

- [ ] Add launch-at-login with a proper login-item helper.
- [ ] Add transfer-aware polling and back off when idle.
- [ ] Watch the SSD mount/unmount state.
- [ ] Send actionable macOS notifications.
- [ ] Add a history view for completed, skipped, and failed jobs.

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

1. Download the completed Put.io file into hidden `.cargo-incoming` staging.
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

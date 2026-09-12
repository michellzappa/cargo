# Cargo plan

## Product definition

Cargo is a quiet, local-first Put.io manager for a Mac that has a removable media SSD shared to Infuse on Apple TV.

The core promise is: **make it obvious what is happening in Put.io, and make bringing completed media home safe and repeatable.**

## Milestones

### 0. Native shell — current

- [x] Create a macOS Swift Package executable.
- [x] Add an AppKit status-item application.
- [x] Add a popover dashboard with remote and local queues.
- [x] Add a durable local state model.
- [x] Add unit-test scaffolding.
- [x] Make Settings mirror the media workflow step by step.

### 1. Put.io read-only integration

- [x] Add manual token setup using the macOS Keychain.
- [x] Fetch account information and remote transfers.
- [ ] Add browser OAuth sign-in with state validation.
- [x] Fetch remote files and folders at the Put.io root.
- [x] Map Put.io statuses into Cargo statuses.
- [ ] Add refresh, retry, cancel, and open-in-browser actions.
- [ ] Keep the app useful when Put.io is unavailable by showing cached state and a stale indicator.

### 2. Local sync pipeline

- [x] Let the user choose and authorize the SSD library root.
- [x] Persist a security-scoped bookmark for the selected volume.
- [x] Add the first local download job execution path.
- [x] Download selected remote files into a hidden staging directory.
- [ ] Add progress, pause, resume, retry, and cancellation.
- [ ] Verify size and/or checksum before import.
- [ ] Resume safely after app restart, SSD removal, or network failure.

### 3. Library organization

- [ ] Add configurable Movies and TV Shows destinations.
- [ ] Identify common movie and episode filename patterns.
- [ ] Preview the proposed destination before moving anything.
- [ ] Move files atomically where possible.
- [ ] Quarantine ambiguous or unsupported files instead of guessing.
- [ ] Detect duplicates and existing library files.
- [ ] Add optional remote cleanup only after verified local import.

### 4. Background operation

- [ ] Add launch-at-login with a proper login-item helper.
- [ ] Poll Put.io while transfers are active and back off when idle.
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

## Settings information architecture

Settings is deliberately a workflow, not a flat list of unrelated preferences:

1. Connect Put.io.
2. Observe remote transfers.
3. Sync completed files to the SSD.
4. Organize the local library.
5. Run post-import automation such as EasySubs.
6. Notify on meaningful changes.

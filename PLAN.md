# Cargo plan

## Product definition

Cargo is a quiet, local-first Put.io manager for a Mac that has a removable media SSD shared to Infuse on Apple TV.

The core promise is: **make it obvious what is happening in Put.io, and make bringing completed media home safe and repeatable.**

## Milestones

### 0. Native shell

- [x] Create a macOS Swift Package executable.
- [x] Add an AppKit status-item application.
- [x] Add a normal dashboard window opened from the menu bar with remote and local queues.
- [x] Add a durable local state model.
- [x] Add unit-test scaffolding.
- [x] Make Settings mirror the media workflow step by step.
- [x] Separate Transfers, Files, Inbox, History, and Settings into focused main-window views.
- [x] Use a native macOS sidebar navigation shell with live queue badges.
- [x] Add reproducible app version and build-number packaging.
- [x] Normalize page spacing, list containers, rows, forms, and controls through shared UI helpers.

### 1. Put.io read-only integration

- [x] Add browser-only OAuth sign-in using the registered Cargo app (`9732`).
- [x] Fetch account information and remote transfers.
- [x] Add browser OAuth sign-in with state validation.
- [x] Fetch remote files and navigate Put.io folders.
- [x] Limit Cargo tracking to video media files while retaining folders for navigation.
- [x] Map Put.io statuses into Cargo statuses.
- [x] Add refresh, retry, cancel, and clean-finished actions.
- [ ] Keep the app useful when Put.io is unavailable by showing cached state and a stale indicator.
- [x] Poll Put.io on a basic fixed interval and update the open dashboard.

### 2. Local sync pipeline

- [x] Let the user choose and authorize the SSD library root.
- [x] Persist a security-scoped bookmark for the selected volume.
- [x] Add the first local download job execution path.
- [x] Download selected remote files into a hidden staging directory.
- [x] Add progress, resume and retry (streamed `.part` files with `Range`); pause and cancellation are still open.
- [x] Verify the local byte size before remote cleanup/import.
- [x] Resume safely after app restart or network failure — interrupted jobs re-queue and continue from the partial. SSD removal mid-download still needs explicit handling.

### 3. Library organization

- [x] Store configurable staging, Movies, and TV Shows folder names.
- [ ] Treat the selected SSD folder as the existing Infuse library root; do not reorganize existing content automatically.
- [ ] Inspect the existing root and learn/confirm its current Movies and TV Shows folders.
- [x] Identify common movie and episode filename patterns, using the filename as the initial signal.
- [x] Show a proposed destination from the configured library layout before moving anything.
- [x] Recursively scan the physical `_Inbox` folder so nested, manually placed, or previously untracked files are visible.
- [x] Ignore non-video Inbox files and sidecars such as subtitles, artwork, metadata, and archives.
- [x] Remove ignored Inbox sidecars and empty nested folders after their final media is organized, while preserving `_Inbox` itself.
- [x] Apply conservative movie and TV episode rename rules during explicit Inbox organization.
- [ ] Confirm finer rename and reorganization rules with the existing Infuse folder layout.
- [x] Move verified files from hidden `_Inbox` into the chosen existing destination after an explicit Organize action.
- [x] Leave ambiguous or unsupported files in `_Inbox` with an explanation instead of guessing.
- [x] Refuse to overwrite an existing destination; smarter duplicate detection (same title, better quality) is still open.
- [x] Delete a copied Put.io media file only after local verification, then remove only empty parent folders.

### 4. Background operation

- [x] Add launch-at-login with the native macOS login-item service.
- [x] Add recursive background polling for newly discovered Put.io media in any folder.
- [ ] Watch the SSD mount/unmount state.
- [x] Send meaningful macOS notifications for workflow changes.
- [x] Add a history view for completed, organized, and failed jobs.

### 5. EasySubs integration

- [x] Confirm the integration contract for EasySubs: EasySubsKit package, subtitles after organize.
- [x] EasySubsKit is a package dependency; subtitles run after organize and a subtitle failure never fails the import.

### 6. Optional metadata/watchlist features

- [x] Sync a public IMDb Watchlist dynamically as a read-only desired list.
- [x] Compare watchlist titles with recursive Put.io media and local Cargo jobs.
- [x] Show Chill release/availability metadata without making Cargo an indexer manager.
- [x] Show Chill's top movie and series catalogs in Discover, with title/year release search.
- [x] Send an explicitly selected Chill release URL to Put.io.
- [ ] Add other list providers only if they solve a real workflow gap.

### 7. Resident remote control

- [x] Define a remote-safe snapshot model that excludes local paths, bookmarks,
  and credentials.
- [x] Define a transport-neutral command interface for refresh, discovery,
  transfers, local sync, organization, and watchlist refresh.
- [x] Add an authenticated embedded read API bound to localhost on the resident Mac.
- [x] Add stable JSON envelopes, request IDs, bounded request bodies, and API
  contract tests.
- [x] Add explicit network scoping (loopback by default or local network) and
  Keychain-backed token rotation controls.
- [x] Expose the transport-neutral commands through an authenticated API route.
- [x] Add a revisioned HTTP event feed and reusable client transport foundation.
- [x] Make Cargo dual-role: the same app can be the resident server, a remote
  client, or both.
- [x] Add same-app client connection settings with a Keychain token, resident
  URL, presence registration, and heartbeat session.
- [x] Add low-information discovery and Tailscale peer auto-find; bearer-token
  pairing remains explicit so discovering a Cargo peer never grants access.
- [x] Add the authenticated presence contract and resident-side client lease
  registry; clients can register, heartbeat, query presence, and unregister.
- [x] Show resident/client connection status and connected-client presence in
  Remote Access settings.
- [x] One-string pairing (`cargo://pair?url=…&token=…`) from the resident, using its Tailscale MagicDNS name.
- [ ] Add revoke/forget controls for individual client registrations.
- [x] Make the normal dashboard render the resident snapshot in client mode
  and route supported dashboard actions through the resident.
- [x] Reuse the same dashboard UI and command models for multiple client
  devices per resident.
- [x] Reconnect: the heartbeat re-registers after a resident restart. Streaming delivery is still open; the revisioned polling feed remains.
- [x] Validated across two Macs over Tailscale (pairing link, per-client search).

## Non-goals for the first release

- indexer management (Chill is the provider)
- implementing torrent/magnet discovery inside Cargo
- replacing Chill or ShowRSS as a discovery service
- Plex/Jellyfin server management
- transcoding
- cloud accounts or multi-tenant permissions (multiple trusted companion
  devices are in scope)
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

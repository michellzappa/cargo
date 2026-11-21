# Changelog

Every entry below is a `v`-prefixed git tag. Add an entry here before you cut
a tag. The app bundles this file for HouseKit (`Changelog.load`).

## Unreleased

### Added

- Added a Subscriptions page on macOS and iOS. Subscribe to a series by name,
  from a show in Library, or from a series in Discover, or add an RSS or
  Atom feed. Pause, resume and unsubscribe from the page. Cargo does not
  fetch episodes for a subscription yet.
- Added `cargo-mcp`, a local MCP server that gives Claude and other agents
  the `cargoctl` commands as tools: status, lists, Put.io listings, logs, and
  resident commands such as Chill search and retrying a transfer.
- Added Reveal in Finder to the transfer context menu.
- Added `cargoctl`, a JSON command line for the running resident, Cargo's state
  file, Put.io's unfiltered listings, and Cargo's log.
- Cargo now checks each download against Put.io's CRC32 and the video
  container header before it removes the Put.io copy. A failed check keeps
  the Put.io copy, deletes the local copy, and fails the job.
- Transfers now show a problem line: Put.io's error message, a torrent with no
  peers and no data for 6 hours, a transfer stuck at 100% for an hour, or a
  finished transfer that holds no usable video. Each problem also warns once
  in History.
- Cargo retries the Put.io delete for a downloaded file that is still on
  Put.io, after it verifies the local copy again.
- Cargo skips a new release of an episode or movie that the library or a
  running download already has, and sends it to the Put.io trash. Of two new
  releases of one episode, it keeps the larger file.
- Added the iOS 17 companion app with resident pairing, Keychain-backed
  credentials, cached snapshots, foreground polling, and dashboard pages for
  transfers, files, library, discovery, watchlist, inbox, history, and
  settings.
- Added per-client reconnect handling and clearer resident connection state.
- Added Apple TV discovery, pairing, and Infuse playback handoff on macOS.
- Added configurable accent colors on macOS and iOS.
- Added persistent, client-scoped personal IMDb watchlists on connected Macs
  and iOS clients.

### Changed

- Unified media rows and startup navigation across the macOS and iOS clients.
- Made iOS filters consistent as leading toolbar controls with native menu
  selection state.
- Improved security-scoped library access and parity between resident and
  remote-client views.
- Improved iOS reconnect and offline/cached-state presentation.
- Kept personal watchlists display-only so they cannot accidentally alter the
  resident's automatic download workflow.
- Cargo's cleanup after a verified download now sends the Put.io copy and its
  empty folders to the Put.io trash instead of deleting them for good. Empty
  the trash in Settings to free the quota.
- A video with no SxxEyy marker and no year now goes to review instead of
  Movies. Rename it with the marker or the year, then organize it.
- Each download now goes to its own folder in `_Inbox`, named by Put.io file
  ID, so two releases with the same file name no longer collide.

### Fixed

- Fixed Cargo freezing at launch, and its API timing out, when the library
  volume blocked file access. The Inbox and library scans now run off the
  main thread.
- Fixed episodic transfer titles to show the series and episode instead of unresolved placeholders.
- Fixed transfers at 1% showing as 100%.
- Fixed Put.io dates without a time zone falling back to the current time.
- Cargo now downloads only the main video. It skips featurettes, specials,
  samples and small extra videos in a movie folder, and sends those and
  leftover release folders to the Put.io trash when remote cleanup is on.
- Fixed transfers and watchlist items matching the wrong poster or file when a short title (such as "Pi") appeared inside another word.
- Kept remote and local dashboard navigation in the same stable product order.
- Preserved the resident's source-of-truth boundaries while adding the mobile
  client, so credentials, bookmarks, and absolute paths stay resident-side.

## 0.8.0 - 2026-09-21

### Added

- Chill discovery: browse movie catalogs with filters, and search per client.
- A local remote API with authentication, so a remote client can control
  Cargo over Tailscale. A pairing link connects a client.
- Downloads resume after an interruption and show live progress.
- Builds carry the git commit they came from.
- Subtitles through EasySubsKit: Put.io's own after a download,
  OpenSubtitles after organize, and Get Subtitles on Library rows.
- Watchlist tabs: All, Wanted, On Put.io and In Library.
- The sidebar footer shows free space on the library volume next to Put.io's.
- Clear Finished (Transfers) and Clear Failed (Inbox) in the page bar.

### Fixed

- Downloads that a quit interrupted go back in the queue on launch.
- Cargo does not empty the trash twice.
- Changes in the Tailscale status format and empty peer lists no longer break
  the remote API.
- Failed state saves show an error. The resident API registers again after a
  restart and rebinds its port at once.
- Plain HTTP is allowed to ts.net and local hosts for the resident API.

## 0.4.0 - 2026-09-14

### Added

- Cargo joins the house apps: XcodeGen, bundle id `app.cargo.Cargo`, HouseKit
  and an install to /Applications.
- Put.io: an activity feed, archive extraction, cleanup that skips the trash,
  and a filtered listing. Background workflow automation.
- Library: the SSD is the source of truth, with TMDB posters, season
  completeness, and tabs for All, Movies, TV Shows, Incomplete and Unmatched.
  Find on Put.io queues missing episodes.
- Watchlist: syncs a public IMDb watchlist, sorts by Recently Added, Year,
  Title or Status, and opens on IMDb for edits.
- History with a Clear button and 30 or 90 day pruning. Inbox can clear
  failed items. Finished transfers can clean up on their own.
- Lists allow multiple selection. Context menu actions apply to every
  selected row, and destructive actions confirm once with the count.
- `cargo://open` and `cargo://snapshot` URLs.

### Fixed

- Settings text fields show their values the first time the window opens.
- List rows keep a fixed 40 by 60 thumbnail.
- The page bar sits below the title bar, not behind it.
- TMDB misses are cached and no longer use up the lookup budget.

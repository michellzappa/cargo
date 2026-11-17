# Changelog

Every entry below is a `v`-prefixed git tag. Add an entry here before you cut
a tag. The app bundles this file for HouseKit (`Changelog.load`).

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

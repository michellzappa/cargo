# Changelog

All notable Cargo changes are documented here. The `Unreleased` section covers
work since the latest tagged release; move it under a dated version heading
when creating the next release.

## [Unreleased]

The next macOS marketing version is `0.9.1`; the iOS companion continues its
independent `0.1.0` marketing line.

### Added

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

### Fixed

- Fixed episodic transfer titles to show the series and episode instead of unresolved placeholders.
- Fixed transfers and watchlist items matching the wrong poster or file when a short title (such as "Pi") appeared inside another word.
- Kept remote and local dashboard navigation in the same stable product order.
- Preserved the resident's source-of-truth boundaries while adding the mobile
  client, so credentials, bookmarks, and absolute paths stay resident-side.

## [0.8.0] - 2026-09-21

### Added

- Added the authenticated resident HTTP API and remote-safe snapshot model.
- Added remote client mode for another Mac, including pairing links, presence
  registration, heartbeat leases, remote dashboard actions, and per-client
  Chill search.
- Added Chill discovery catalogs and release search with explicit Put.io
  handoff.
- Added resumable downloads, archive extraction, subtitle handling, library
  metadata, and richer watchlist/library workflow views.
- Added transfer cleanup, failed-job cleanup, interrupted-download recovery,
  SSD free-space visibility, and safe remote deletion after local verification.
- Added Tailscale discovery, pairing URLs, network-scope controls, token
  rotation, presence leases, reconnect registration, and event-feed polling.

### Changed

- Made state saves recoverable with backups and preserved corrupt state files.
- Stamped release builds with their source commit and moved the coordinator
  into concern-specific files.

### Fixed

- Hardened state persistence by surfacing save failures, retaining backups, and
  preserving undecodable state files instead of overwriting them.
- Made Chill search per-client so searches on connected devices do not fight
  over the resident's Discover page.
- Made the HTTP server rebind reliably after restart and tolerated Tailscale
  status and empty-peer-list variations.

## [0.7.0] - 2026-09-20 milestone

### Added

- Added Chill discovery with searchable release results, movie and series
  catalogs, metadata, filters, and explicit Put.io handoff.
- Added the authenticated local remote-control API foundation and remote-safe
  snapshot contract.

### Changed

- Refined Discover browsing and filter controls around title/year release
  selection rather than making Cargo an indexer manager.

## [0.4.0] - 2026-09-14

### Added

- Added the local SSD library workflow: staging, organization, verification,
  cleanup, and library browsing.
- Added public IMDb watchlist synchronization and wanted-title tracking.
- Added Put.io transfer, file, inbox, and background automation workflows.

### Changed

- Reworked the dashboard around workflow pages with native AppKit tables,
  sidebar navigation, toolbar actions, selection handling, and a persistent
  menu-bar resident.
- Added XcodeGen, HouseKit integration, stable signed local builds, CI
  build/test validation, and the first notarized-release workflow.

## [0.3.6] - 2026-09-13 milestone

### Added

- Added library folder selection, IMDb watchlist editing/opening, sorting,
  TMDB-backed posters and completeness, unmatched-title handling, and
  multi-selection actions.
- Added the first public-release packaging path: generated Xcode projects,
  signed app installation, app icon generation, and About-page repository
  links.

### Changed

- Consolidated Cargo around the menu-bar workflow and shared HouseKit settings
  chrome, with launch-at-login and notification controls.

## [0.3.0] - 2026-09-12 milestone

### Added

- Added browser-based Put.io authorization, account/transfer refresh, remote
  folder navigation, and the initial periodic background cycle.
- Added the local `_Inbox` staging workflow with release-name parsing,
  movie/TV organization previews, actionable organization, and video-only
  inventory tracking.
- Added recursive Put.io media inventory, a public IMDb watchlist source, and
  the first watchlist-to-download matching workflow.

### Changed

- Moved from a prototype dashboard to a safe automation model that only
  deletes remote media after the local copy has been verified.

## Initial foundation - 2026-09-12

- Established the native AppKit menu-bar shell, dashboard window, settings
  window, transfer list, Put.io client boundary, and local state model.
- Added reproducible build identity stamping and the first About/build
  information surface.

[Unreleased]: https://github.com/michellzappa/cargo/compare/v0.8.0...HEAD
[0.8.0]: https://github.com/michellzappa/cargo/releases/tag/v0.8.0
[0.7.0]: https://github.com/michellzappa/cargo/compare/v0.4.0...0e20793
[0.4.0]: https://github.com/michellzappa/cargo/releases/tag/v0.4.0

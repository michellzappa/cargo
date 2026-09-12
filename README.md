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
- popover dashboard
- persisted local state store
- remote transfer and local sync job models
- Keychain-backed Put.io token storage
- read-only Put.io account and transfer refresh
- remote root file browsing with idempotent local-sync queueing
- SSD library-root selection with a persisted security-scoped bookmark
- first local handoff into a hidden SSD staging directory
- build and test target
- documented implementation plan and known risks

OAuth browser sign-in, resumable downloads, and library organization are the next implementation steps.

## Build

```sh
swift build
swift test
```

The executable can be run directly from the build directory, although a proper `.app` bundle and login item will be added before distribution.

## Product boundary

Cargo does not currently discover releases, parse ShowRSS feeds, or submit magnets. Those responsibilities stay upstream in ShowRSS and Put.io. Cargo observes the resulting Put.io state and manages the local library handoff.

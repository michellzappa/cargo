# Cargo build issues and risks

This is the implementation ledger for risks that can affect the native Mac build.

## Put.io authentication

The app needs a secure OAuth/token flow. Tokens must live in Keychain, never in the JSON state file or logs. We should build the client behind a protocol so the UI can be tested with fixtures without requiring a live account.

## Put.io API semantics

Put.io has separate concepts for transfers and files. A completed transfer may produce a folder tree, and a remote file may not have enough metadata to identify its movie or episode reliably. The client must preserve raw IDs and names and avoid treating filenames as stable identity.

## Local SSD permissions

The SSD may be removed, renamed, or mounted at a different path. A sandboxed app needs a security-scoped bookmark created from an `NSOpenPanel`. All file access should go through a small authorization/path layer.

## Resumable downloads

Local Put.io downloads can be interrupted by sleep, network changes, app termination, or SSD removal. The downloader needs temporary files, resume support, cancellation, and a final atomic rename so incomplete files never appear in the Infuse library.

## Media identification

Release names are messy. A parser should produce confidence and candidates, not pretend every filename is unambiguous. Low-confidence files should land in a review/quarantine area.

## Duplicate and retry behavior

Polling must be idempotent. A job should have a stable remote-file identity and a local destination identity. Retries must not create a second copy or overwrite a better existing file silently.

## Remote deletion safety

Deleting from Put.io is irreversible from Cargo's perspective. It should be disabled by default, require a separate setting, and only be available after local verification and a visible confirmation.

## Background execution

The app should run in the user's GUI session rather than relying on a detached shell job. Launch-at-login, sleep/wake, and removable-volume behavior need explicit testing on a real Mac.

## EasySubs contract

The public EasySubs repository found during planning appears to be a browser extension. Before integrating it, confirm whether the desired future integration is subtitle acquisition, subtitle placement, or launching a title in EasySubs. The Cargo core should expose a generic post-import job boundary regardless.

## Distribution

Before sharing outside the development machine, Cargo needs an `.app` bundle, signing/notarization decisions, privacy messaging, and a clear policy for App Sandbox versus a direct-download build.

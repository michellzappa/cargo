# Cargo build issues and risks

This is the implementation ledger for risks that can affect the native Mac build.

## Put.io authentication

Cargo supports a browser OAuth flow using the `cargo://oauth/callback` scheme and stores the resulting access token in Keychain, never in the JSON state file or logs. The flow still needs validation against a real Put.io OAuth app because provider-side redirect registration and implicit-flow behavior cannot be tested without the user's app ID.

## Put.io API semantics

Put.io has separate concepts for transfers and files. A completed transfer may produce a folder tree, and a remote file may not have enough metadata to identify its movie or episode reliably. The client must preserve raw IDs and names and avoid treating filenames as stable identity.

## Local SSD permissions

Cargo now stores the selected SSD folder as a security-scoped bookmark and uses it for the first staging download path. The authorization layer still needs stale-bookmark repair and explicit unmounted-volume handling. Progress and resumable downloads are also still pending.

## Resumable downloads

Settled: downloads stream into `<name>.part` in `_Inbox`, resume with a `Range` request, and only rename to the final name once complete, so partials never appear in the Infuse library. Interrupted jobs re-queue themselves up to eight times. Still open: cancellation, and SSD removal mid-write (the `.part` then lives on a vanished volume).

## Media identification

Release names are messy. A parser should produce confidence and candidates, not pretend every filename is unambiguous. Low-confidence files should land in a review/quarantine area.

## Duplicate and retry behavior

Polling must be idempotent. A job should have a stable remote-file identity and a local destination identity. Retries must not create a second copy or overwrite a better existing file silently.

## Remote deletion safety

Deleting from Put.io is irreversible from Cargo's perspective. It should be disabled by default, require a separate setting, and only be available after local verification and a visible confirmation.

## Background execution

The app should run in the user's GUI session rather than relying on a detached shell job. Launch-at-login, sleep/wake, and removable-volume behavior need explicit testing on a real Mac.

## Remote control

The resident API is loopback-only by default. Settings can explicitly widen it
to the local network, where the Mac firewall and the Keychain-backed bearer
token remain part of the security boundary. The API has a command route for the
existing transport-neutral command model and a revisioned event feed.

The client should be another instance of the same Cargo app, not a separate
product: one installation owns the resident state, while any number of trusted
installations can connect as remote clients. Pairing should register each
client with the resident, show connected clients on the resident, show the
connected resident on each client, and support revoke/forget. Pairing is one
copyable `cargo://pair` link; presence registration, heartbeat with
re-registration after a resident restart, Tailscale auto-find and the same-app
remote dashboard are in place and tested across two Macs over Tailscale. Two
things to remember: the App Store Tailscale binary only behaves as a CLI when
`SHLVL` is set (Cargo sets it), and ATS needs the `ts.net` exception in
Info.plist for plain HTTP to a tailnet name. Streaming delivery and
revoke/forget controls are still pending.

## EasySubs contract

Settled: EasySubs is `michellzappa/easysubs`, and its engine is the `EasySubsKit` Swift package Cargo depends on as a sibling (`../easysubs`). Cargo fetches subtitles after organizing — Put.io's own first, OpenSubtitles second. Credentials live in Settings → Library (password in Keychain).

# Changelog

All notable changes to Secure Tiles are recorded in this file.

## 0.3.0 - 2026-08-14

- Fixed installer and portable updates failing before replacement because the hidden PowerShell helper used a reserved process variable.
- Added reliable relaunching after both silent installer updates and portable executable replacement.
- Reduced active-conversation message polling from 2.5 seconds to half a second, with adaptive idle and background polling to conserve relay capacity.
- Added animated three-dot typing indicators using short-lived end-to-end encrypted and signed typing signals.
- Added encrypted live presence with avatar badges for Online, Away, Do Not Disturb, Invisible, and offline states.
- Moved message search and Profile controls to the conversation header and made incoming sender names and avatars open contact profiles.
- Added focused hover feedback for clickable sender names and avatars without highlighting entire message rows.
- Added true circular masking for square profile images while keeping presence badges outside the crop.

## 0.2.2 - 2026-08-14

- Fixed existing accounts sometimes being absent from the hosted username directory after upgrading.
- Added safe public-identity registration on every successful unlock so directory entries repair themselves automatically.
- Separated contact initials into compact avatar circles so they no longer appear to be part of usernames.

## 0.2.1 - 2026-08-14

- Added an always-online Cloudflare Worker relay that connects automatically on first launch.
- Migrated existing accounts using the bundled local relay to the hosted relay after their next successful unlock.
- Reduced the combined attachment limit from 200 MB to 50 MB per message.
- Added automatic removal of hosted attachment chunks after the recipient verifies the completed download.

## 0.2.0 - 2026-08-14

- Added end-to-end encrypted file and image attachments with a combined limit of 200 MB per message.
- Added resumable one-megabyte attachment chunks, authenticated encryption, and signed SHA-256 reconstruction checks.
- Added attachment upload and download progress, retry support, local history, image previews, and Save As controls.
- Added a full-screen image viewer with panning, mouse-wheel zoom, fit controls, and keyboard dismissal.
- Added optional Send and formatting controls with persistent Appearance settings.
- Refined the message composer and redesigned Settings with flatter navigation, clearer grouping, and accessible state indicators.
- Added separate Windows installer and portable executable release formats.
- Updated automatic releases to download and apply the appropriate installer or portable executable.

## 0.1.0 - 2026-08-13

- Introduced the Secure Tiles encrypted desktop messenger for Windows.
- Added Curve25519 message encryption, Ed25519 signatures, Argon2id vault protection, and contact safety numbers.
- Added username discovery, pinned contact identities, encrypted message delivery, local message history, and a bundled loopback relay.
- Added configurable themes, profiles, privacy controls, notifications, and automatic release checks.

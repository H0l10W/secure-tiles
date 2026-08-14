# Changelog

All notable changes to Secure Tiles are recorded in this file.

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

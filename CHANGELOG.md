# Changelog

All notable changes to Nightseal are recorded in this file.

## 0.5.0 - 2026-08-16

- Rebranded the application from Secure Tiles to Nightseal with the tagline “Private conversations. Keys stay yours”.
- Added a new Nightseal logo across the application interface, Windows executable metadata, installer, and release assets.
- Kept transition release aliases so existing Secure Tiles installations can discover and install the Nightseal update.
- Added a cohesive design system with consistent typography, spacing, controls, Fluent-style icons, headers, menus, and modal presentation.
- Improved narrow-window behavior across authentication, contacts, conversations, servers, profiles, settings, and popups.
- Refined contact selection, empty states, message presentation, composer actions, attachment controls, and settings organization.
- Removed routine inline success notices while retaining actionable warnings and failures.
- Fixed compact formatting controls overlapping or displaying off-center text.
- Fixed conversations scrolling away from the newest message after sending or after attachment previews resize.

## 0.4.0 - 2026-08-15

- Added early-development servers with server creation, invite joining, server discovery, and dedicated server navigation.
- Added text and voice channel management, channel topics, encrypted server messaging, and member-aware message delivery.
- Added configurable roles and permissions, member role assignment, server profiles, and server administration controls.
- Added signed, time-limited, replay-resistant server actions across the local relay and Cloudflare relay implementations.
- Added persistent server, channel, role, invite, membership, and server-message storage with expanded protocol and relay tests.
- Refined the application interface to support server lists, channel views, member lists, server settings, and server-specific conversation states.
- Server features are still early in development and may change significantly in future releases.

## 0.3.7 - 2026-08-15

- Added dedicated People and Favorites sidebar tabs with a finished empty-favorites state.
- Kept normal contact avatars visible when favorited instead of replacing them with a star.
- Added encrypted sharing and rendering of profile bios, pronouns, custom statuses, status emoji, banner colors, avatars, banners, and profile backgrounds.
- Added a customized Cipher Bot profile for testing shared profile presentation.
- Redesigned the application header, sidebar, account bar, settings navigation, contact profiles, chat surfaces, and interaction states for a cohesive professional interface.
- Rebalanced custom colors into readable tinted controls with visible borders and restrained selected states.
- Fixed theme colors becoming transparent because QML received string values instead of color objects.
- Added persistent readable settings cards and stronger content surfaces over detailed wallpapers.
- Increased body, control, sidebar, message, label, and settings text sizes for improved clarity.
- Added full font hinting, a consistent Segoe UI fallback, and pass-through high-DPI scaling for crisp Windows rendering.
- Fixed a stale message-composer focus binding that produced runtime warnings.

## 0.3.6 - 2026-08-14

- Fixed Restart to update closing both installed and portable builds without completing the update or relaunching the application.
- Replaced the fragile detached updater process mode with a checked background handoff that remains alive after the application exits.
- Added updater failure logs and immediate error reporting when the update helper cannot start.
- Increased installer and portable replacement wait times and relaunch the application from its correct working directory.
- Added a Windows integration test that verifies the updater survives launcher exit, replaces the target, and relaunches it.

## 0.3.5 - 2026-08-14

- Added custom application wallpapers, including animated GIF support, with adjustable wallpaper visibility.
- Added separate custom accent, application background, buttons and inputs, and conversation background colors.
- Added independent opacity controls for panels, buttons and inputs, wallpaper, and conversation backgrounds.
- Added custom profile banner images, animated banners, full-profile backgrounds, and removable profile media.
- Added Modern, Heavy Metal, Vampire, Arcade, and Cipher display-name styles with encrypted sharing between contacts.
- Added a dedicated Friends view with responsive contact cards and live presence indicators.
- Refined Settings with compact controls, responsive profile actions, shorter toggles, grouped sections, and consistently sized sliders.
- Added theme-aware tonal shading, subtle borders, and restrained color hierarchy for buttons, inputs, panels, and navigation controls.
- Added custom circular profile pictures to outgoing message rows.
- Added persistent per-conversation unread counters in the people sidebar.
- Added incoming-message notification sounds that respect the Message sounds preference and remain silent during Do Not Disturb.
- Improved wallpaper replacement and removal so Windows file locks no longer surface as application errors.

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

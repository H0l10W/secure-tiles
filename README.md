# Secure Tiles

A modern, Qt Quick desktop messenger with end-to-end encrypted delivery and username discovery. It uses PyNaCl/libsodium rather than implementing cryptography itself. Its PySide6/QML interface is hardware accelerated, DPI aware, and responsive during live window resizing.

## Security design

- Curve25519 `Box` authenticated public-key encryption (XSalsa20-Poly1305)
- Ed25519 signatures bind each message to the saved contact identity
- Argon2id derives the local vault key from the user's passphrase
- SecretBox encrypts private identity keys at rest
- Contact safety numbers allow out-of-band identity verification
- Unknown senders, altered packets, wrong recipients, stale timestamps, and duplicate message IDs are rejected
- File names, contents, and image attachments are signed and end-to-end encrypted with their message
- No analytics, key escrow, recovery key, or hidden network traffic
- Username identities are pinned on first contact; changed keys are rejected

This is an auditable MVP, not a professionally audited replacement for Signal. The relay sees usernames, public keys, traffic timing, sender/recipient keys, packet sizes, and ciphertext—but not message plaintext, attachment contents, file names, or private keys. Decrypted message history and attachments are stored locally; full-disk encryption is recommended. A message can contain up to five files with a combined size of 50 MB. Remote attachments use independently encrypted 1 MB chunks; retrying a failed send resumes from the chunks already accepted by the relay, and the receiver verifies the reconstructed file against its signed SHA-256 digest.

## Run

```powershell
python -m pip install -r requirements.txt
python main.py
```

On first launch, choose a unique username and a strong vault passphrase. The app connects automatically to the hosted Cloudflare relay, so users on different computers can find and message one another without configuring a server address. Add another registered user by typing only their username. The app fetches and pins their signed public identity in a background worker. Compare the displayed safety number over a trusted channel for stronger protection against a malicious first lookup.

Release downloads provide a per-user Windows installer and a standalone portable executable. See `CHANGELOG.md` for the complete version history.

## Updates and releases

Secure Tiles checks the public `H0l10W/secure-tiles` GitHub Releases feed after startup. A newer version is downloaded in the background, checked against the SHA-256 digest returned by GitHub, and extracted with path-traversal and size protections. The application is only replaced after the user chooses **Restart to update**. Replaced files are backed up under `~/.secure_tiles/update_backups`.

Pushing to `main` runs the Windows test suite. When the version in `secure_tiles/__init__.py` has not been released before, the workflow creates a matching GitHub Release and attaches the installer, portable executable, and changelog. Bump `__version__` and update `CHANGELOG.md` before pushing a new release.

The default relay runs as a Cloudflare Worker backed by D1 and stores only public contact cards, opaque encrypted packets, and independently encrypted attachment chunks. Its source and deployment configuration are under `cloudflare/`. The bundled Python relay remains available for development with `python relay_server.py`, but released clients use the hosted HTTPS relay automatically.

## Threat-model boundaries

The app protects message contents against an untrusted transport and detects packet tampering. It cannot protect an unlocked or malware-infected computer, a stolen passphrase, screen capture, traffic metadata, or a contact who shares plaintext. Deleting a message from this app cannot guarantee removal from storage media or the recipient's device.

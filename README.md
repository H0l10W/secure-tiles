# Secure Tiles

A modern, Qt Quick desktop messenger with end-to-end encrypted delivery and username discovery. It uses PyNaCl/libsodium rather than implementing cryptography itself. Its PySide6/QML interface is hardware accelerated, DPI aware, and responsive during live window resizing.

## Security design

- Curve25519 `Box` authenticated public-key encryption (XSalsa20-Poly1305)
- Ed25519 signatures bind each message to the saved contact identity
- Argon2id derives the local vault key from the user's passphrase
- SecretBox encrypts private identity keys at rest
- Contact safety numbers allow out-of-band identity verification
- Unknown senders, altered packets, wrong recipients, stale timestamps, and duplicate message IDs are rejected
- No analytics, key escrow, recovery key, or hidden network traffic
- Username identities are pinned on first contact; changed keys are rejected

This is an auditable MVP, not a professionally audited replacement for Signal. The relay sees usernames, public keys, traffic timing, sender/recipient keys, and ciphertext—but not message plaintext or private keys. Message plaintext history is currently stored locally in SQLite after decryption; full-disk encryption is recommended.

## Run

```powershell
python -m pip install -r requirements.txt
python main.py
```

The app automatically starts the bundled local relay on `127.0.0.1:8765` in a background thread, without opening another window. If that address is already occupied by a running relay, the app reuses it. On first launch, choose a unique username and a strong vault passphrase. Add another registered user by typing only their username. The app fetches and pins their signed public identity in a background worker. Compare the displayed safety number over a trusted channel for stronger protection against a malicious first lookup.

## Updates and releases

Secure Tiles checks the public `H0l10W/secure-tiles` GitHub Releases feed after startup. A newer version is downloaded in the background, checked against the SHA-256 digest returned by GitHub, and extracted with path-traversal and size protections. The application is only replaced after the user chooses **Restart to update**. Replaced files are backed up under `~/.secure_tiles/update_backups`.

Pushing to `main` runs the Windows test suite. When the version in `secure_tiles/__init__.py` has not been released before, the workflow creates a matching GitHub Release and attaches `secure-tiles-windows.zip`. Bump `__version__` before pushing a new release.

The automatic relay is local-only, so it is suitable for clients on the same computer. For communication between computers, run `python relay_server.py --host 0.0.0.0` on a server, protect it with an HTTPS reverse proxy, and point each client at that HTTPS URL. The server is multithreaded and stores only public contact cards and opaque encrypted packets.

## Threat-model boundaries

The app protects message contents against an untrusted transport and detects packet tampering. It cannot protect an unlocked or malware-infected computer, a stolen passphrase, screen capture, traffic metadata, or a contact who shares plaintext. Deleting a message from this app cannot guarantee removal from storage media or the recipient's device.

# Secure Tiles Cloudflare relay

This Worker provides the public username directory and opaque encrypted-message relay used by released Secure Tiles clients. D1 stores public contact cards, encrypted message envelopes, and encrypted one-megabyte attachment chunks. Successfully downloaded attachments are removed immediately, while scheduled cleanup removes abandoned transfers after seven days and messages after thirty days.

To redeploy from this directory:

```powershell
npx wrangler d1 execute secure-tiles-relay --remote --file schema.sql
npx wrangler deploy
```

The production health endpoint is:

`https://secure-tiles-relay.secure-tiles-cloudflare-relay.workers.dev/health`

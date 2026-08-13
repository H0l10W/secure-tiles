"""Non-blocking-friendly client for the untrusted ciphertext relay."""

from __future__ import annotations

import json
import urllib.error
import urllib.parse
import urllib.request
from typing import Any


class RelayError(RuntimeError):
    pass


class RelayClient:
    def __init__(self, base_url: str):
        self.base_url = base_url.rstrip("/")

    def _request(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        data = json.dumps(body).encode("utf-8") if body is not None else None
        request = urllib.request.Request(
            self.base_url + path, data=data, method=method,
            headers={"Content-Type": "application/json", "User-Agent": "SecureTiles/0.2"},
        )
        try:
            with urllib.request.urlopen(request, timeout=8) as response:
                return json.loads(response.read().decode("utf-8"))
        except urllib.error.HTTPError as exc:
            try:
                detail = json.loads(exc.read().decode("utf-8")).get("error", str(exc))
            except Exception:
                detail = str(exc)
            finally:
                exc.close()
            raise RelayError(detail) from exc
        except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
            raise RelayError(f"Relay unavailable: {exc}") from exc

    def register(self, card: dict[str, Any]) -> None:
        self._request("PUT", "/v1/users", card)

    def lookup(self, username: str) -> dict[str, str]:
        name = urllib.parse.quote(username.lower(), safe="")
        return self._request("GET", f"/v1/users/{name}")

    def send(self, envelope: dict[str, Any]) -> None:
        self._request("POST", "/v1/messages", envelope)

    def inbox(self, encryption_key: str) -> list[dict[str, Any]]:
        key = urllib.parse.quote(encryption_key, safe="")
        return self._request("GET", f"/v1/messages/{key}").get("messages", [])

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
            timeout = 120 if "/attachments/" in path or (data and len(data) > 1_000_000) else 8
            with urllib.request.urlopen(request, timeout=timeout) as response:
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

    def send_typing(self, envelope: dict[str, Any]) -> None:
        self._request("POST", "/v1/typing", envelope)

    def send_presence(self, envelope: dict[str, Any]) -> None:
        self._request("POST", "/v1/presence", envelope)

    def begin_attachment(self, attachment_id: str, token: str, recipient: str, total_size: int, chunks: int) -> None:
        self._request("POST", f"/v1/attachments/{attachment_id}/begin",
                      {"token": token, "recipient": recipient, "total_size": total_size, "chunks": chunks})

    def attachment_status(self, attachment_id: str, token: str) -> set[int]:
        result = self._request("POST", f"/v1/attachments/{attachment_id}/status", {"token": token})
        return {int(index) for index in result.get("received", [])}

    def upload_attachment_chunk(self, attachment_id: str, token: str, index: int, data: str) -> None:
        self._request("POST", f"/v1/attachments/{attachment_id}/chunk",
                      {"token": token, "index": index, "data": data})

    def download_attachment_chunk(self, attachment_id: str, token: str, index: int) -> str:
        return str(self._request("POST", f"/v1/attachments/{attachment_id}/download",
                                 {"token": token, "index": index})["data"])

    def complete_attachment(self, attachment_id: str, token: str) -> None:
        self._request("POST", f"/v1/attachments/{attachment_id}/complete", {"token": token})

    def inbox(self, encryption_key: str) -> list[dict[str, Any]]:
        return self.inbox_state(encryption_key).get("messages", [])

    def inbox_state(self, encryption_key: str) -> dict[str, Any]:
        key = urllib.parse.quote(encryption_key, safe="")
        result = self._request("GET", f"/v1/messages/{key}")
        return {"messages": result.get("messages", []), "typing": result.get("typing", []),
                "presence": result.get("presence", [])}

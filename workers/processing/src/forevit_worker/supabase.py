"""Small Supabase REST client; never includes response bodies or credentials in errors."""
from __future__ import annotations

import time
from dataclasses import dataclass
from urllib.parse import quote

import requests


class SafeRestError(Exception):
    def __init__(self, status: int | None = None):
        self.status = status
        super().__init__(f"supabase_request_failed:{status or 'network'}")


@dataclass(frozen=True)
class Settings:
    supabase_url: str
    service_role_key: str
    worker_id: str
    poll_seconds: float = 3.0
    request_timeout: float = 20.0
    max_file_bytes: int = 25 * 1024 * 1024
    deepseek_api_key: str | None = None
    ai_enabled: bool = False
    deepseek_base_url: str = "https://api.deepseek.com"
    deepseek_model: str = "deepseek-chat"
    max_tokens: int = 1200
    chunk_chars: int = 1400
    chunk_overlap: int = 180

    @classmethod
    def from_env(cls) -> "Settings":
        import os
        url = os.getenv("SUPABASE_URL", "").strip().rstrip("/")
        key = os.getenv("SUPABASE_SERVICE_ROLE_KEY", "").strip()
        if not url or not key:
            raise ValueError("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required")
        if not (url.startswith("https://") or url.startswith("http://localhost") or url.startswith("http://127.0.0.1")):
            raise ValueError("SUPABASE_URL must use HTTPS (localhost is allowed for development)")
        def bounded(name: str, default: int, low: int, high: int) -> int:
            try:
                return max(low, min(high, int(os.getenv(name, str(default)))))
            except ValueError:
                return default
        try:
            poll = float(os.getenv("WORKER_POLL_SECONDS", "3"))
            timeout = float(os.getenv("HTTP_TIMEOUT_SECONDS", "20"))
        except ValueError:
            poll, timeout = 3.0, 20.0
        from uuid import UUID, uuid4
        raw_worker = os.getenv("WORKER_ID", "").strip()
        try:
            worker_id = str(UUID(raw_worker)) if raw_worker else str(uuid4())
        except ValueError as exc:
            raise ValueError("WORKER_ID must be a UUID") from exc
        base = os.getenv("DEEPSEEK_BASE_URL", "https://api.deepseek.com").strip().rstrip("/")
        if not base.startswith("https://"):
            raise ValueError("DEEPSEEK_BASE_URL must use HTTPS")
        return cls(
            supabase_url=url, service_role_key=key, worker_id=worker_id,
            poll_seconds=max(0.25, min(60.0, poll)),
            request_timeout=max(2.0, min(120.0, timeout)),
            max_file_bytes=bounded("MAX_FILE_BYTES", 25 * 1024 * 1024, 1024, 100 * 1024 * 1024),
            deepseek_api_key=os.getenv("DEEPSEEK_API_KEY", "").strip() or None,
            ai_enabled=os.getenv("AI_ENABLED", "false").strip() == "true",
            deepseek_base_url=base,
            deepseek_model=os.getenv("DEEPSEEK_MODEL", "deepseek-chat").strip() or "deepseek-chat",
            max_tokens=bounded("DEEPSEEK_MAX_TOKENS", 1200, 128, 4096),
            chunk_chars=bounded("CHUNK_CHARS", 1400, 250, 6000),
            chunk_overlap=bounded("CHUNK_OVERLAP", 180, 0, 1000),
        )


class Supabase:
    def __init__(self, settings: Settings):
        self.settings = settings
        self.session = requests.Session()
        self.session.headers.update({
            "apikey": settings.service_role_key,
            "Authorization": f"Bearer {settings.service_role_key}",
            "Content-Type": "application/json",
        })

    def _request(self, method: str, path: str, *, params=None, json=None, headers=None, stream=False):
        try:
            response = self.session.request(
                method, self.settings.supabase_url + path, params=params, json=json,
                headers=headers, timeout=self.settings.request_timeout, stream=stream,
            )
        except requests.RequestException as exc:
            raise SafeRestError() from exc
        if not response.ok:
            status = response.status_code
            response.close()
            raise SafeRestError(status)
        return response

    def rpc_claim(self, rpc_name: str, worker_id: str) -> dict | None:
        if rpc_name not in {"claim_ai_job", "claim_document_processing_job"}:
            raise ValueError("unsupported claim RPC")
        response = self._request("POST", f"/rest/v1/rpc/{rpc_name}", json={"p_worker_id": worker_id})
        try:
            data = response.json()
        except ValueError as exc:
            raise SafeRestError(response.status_code) from exc
        finally:
            response.close()
        if data is None or data == []:
            return None
        if isinstance(data, dict):
            return data
        if isinstance(data, list) and len(data) == 1 and isinstance(data[0], dict):
            return data[0]
        raise SafeRestError(200)

    def select(self, table: str, *, params: dict) -> list[dict]:
        response = self._request("GET", f"/rest/v1/{table}", params={"select": "*", **params})
        try:
            data = response.json()
        except ValueError as exc:
            raise SafeRestError(response.status_code) from exc
        finally:
            response.close()
        if not isinstance(data, list):
            raise SafeRestError(200)
        return data

    def insert(self, table: str, rows: dict | list[dict], *, on_conflict: str | None = None) -> None:
        params = {"on_conflict": on_conflict} if on_conflict else None
        headers = {"Prefer": "resolution=merge-duplicates,return=minimal" if on_conflict else "return=minimal"}
        response = self._request("POST", f"/rest/v1/{table}", params=params, json=rows, headers=headers)
        response.close()

    def update(self, table: str, filters: dict, values: dict) -> None:
        params = {**filters, "select": "id"}
        response = self._request("PATCH", f"/rest/v1/{table}", params=params, json=values,
                                 headers={"Prefer": "return=minimal"})
        response.close()

    def update_matching(self, table: str, filters: dict, values: dict) -> bool:
        """Update matching rows and report whether a lease-fenced row was changed."""
        params = {**filters, "select": "id"}
        response = self._request("PATCH", f"/rest/v1/{table}", params=params, json=values,
                                 headers={"Prefer": "return=representation"})
        if response.status_code == 204:
            response.close()
            return False
        try:
            result = response.json()
        except ValueError as exc:
            raise SafeRestError(response.status_code) from exc
        finally:
            response.close()
        return isinstance(result, list) and len(result) > 0

    def storage_download(self, bucket: str, storage_path: str, max_bytes: int) -> bytes:
        # Encode each path component independently to preserve separators and avoid traversal.
        bucket_part = quote(bucket, safe="")
        path_part = "/".join(quote(part, safe="") for part in storage_path.split("/"))
        response = self._request("GET", f"/storage/v1/object/{bucket_part}/{path_part}", stream=True)
        try:
            declared = response.headers.get("Content-Length")
            if declared and int(declared) > max_bytes:
                raise SafeRestError(413)
            parts, size = [], 0
            for block in response.iter_content(chunk_size=64 * 1024):
                if not block:
                    continue
                size += len(block)
                if size > max_bytes:
                    raise SafeRestError(413)
                parts.append(block)
            return b"".join(parts)
        finally:
            response.close()

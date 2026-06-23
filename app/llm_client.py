from typing import Any

import httpx

from app.config import Settings


class LLMClient:
    def __init__(self, settings: Settings, client: httpx.AsyncClient | None = None) -> None:
        self._settings = settings
        self._client = client
        self._owns_client = client is None

    async def __aenter__(self) -> "LLMClient":
        if self._client is None:
            self._client = httpx.AsyncClient(
                base_url=self._settings.inference_base_url.rstrip("/"),
                headers=self._build_headers(),
                timeout=httpx.Timeout(self._settings.primary_timeout_seconds),
            )
        return self

    async def __aexit__(self, *args: object) -> None:
        if self._owns_client and self._client is not None:
            await self._client.aclose()

    def _build_headers(self) -> dict[str, str]:
        headers = {"Content-Type": "application/json"}
        if self._settings.inference_api_key:
            headers["Authorization"] = f"Bearer {self._settings.inference_api_key}"
        return headers

    async def chat_completion(
        self,
        payload: dict[str, Any],
        *,
        model: str,
        timeout: float | None = None,
    ) -> dict[str, Any]:
        if self._client is None:
            raise RuntimeError("LLMClient is not initialized")

        body = {**payload, "model": model, "stream": False}
        request_timeout = timeout or self._settings.primary_timeout_seconds

        response = await self._client.post(
            "/v1/chat/completions",
            json=body,
            timeout=request_timeout,
        )
        response.raise_for_status()
        return response.json()

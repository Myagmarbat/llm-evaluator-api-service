"""Live integration tests against a deployed App Platform instance.

Set INTEGRATION_APP_URL to run, for example:
  INTEGRATION_APP_URL=https://llm-eval-api-dev-8d2f6.ondigitalocean.app pytest tests/integration/test_live_api.py -m live -v

Optional:
  RUN_LIVE_CHAT=1  — also exercise POST /v1/chat (calls inference API, may incur cost)
"""

import asyncio
import os

import httpx
import pytest

pytestmark = pytest.mark.live

APP_URL = os.environ.get("INTEGRATION_APP_URL", "").rstrip("/")
RUN_LIVE_CHAT = os.environ.get("RUN_LIVE_CHAT", "").lower() in {"1", "true", "yes"}


@pytest.fixture
async def live_client():
    if not APP_URL:
        pytest.skip("INTEGRATION_APP_URL is not set")
    timeout = httpx.Timeout(120.0, connect=30.0)
    async with httpx.AsyncClient(base_url=APP_URL, timeout=timeout) as client:
        yield client


class TestLiveHealth:
    async def test_health(self, live_client: httpx.AsyncClient) -> None:
        response = await live_client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"


class TestLiveMetrics:
    async def test_metrics_schema(self, live_client: httpx.AsyncClient) -> None:
        response = await live_client.get("/metrics")
        assert response.status_code == 200
        metrics = response.json()
        for key in (
            "total_requests",
            "shadow_submitted",
            "shadow_dropped",
            "shadow_errors",
            "total_comparisons",
            "total_matches",
            "match_rate_percent",
            "shadow_queue_depth",
        ):
            assert key in metrics


class TestLiveConfig:
    async def test_get_config(self, live_client: httpx.AsyncClient) -> None:
        response = await live_client.get("/config")
        assert response.status_code == 200
        config = response.json()
        assert 0 <= config["shadow_routing_percentage"] <= 100
        assert config["shadow_queue_max_size"] >= 1


class TestLiveChat:
    async def test_chat_completion(self, live_client: httpx.AsyncClient) -> None:
        if not RUN_LIVE_CHAT:
            pytest.skip("Set RUN_LIVE_CHAT=1 to run live LLM chat integration test")

        response = await live_client.post(
            "/v1/chat",
            json={
                "messages": [
                    {
                        "role": "user",
                        "content": 'Reply with JSON only: {"action": "buy"}',
                    }
                ],
                "temperature": 0,
            },
        )
        assert response.status_code == 200
        body = response.json()
        assert "choices" in body
        assert body["choices"][0]["message"]["content"]

        await asyncio.sleep(3)
        metrics = (await live_client.get("/metrics")).json()
        assert metrics["total_requests"] >= 1
        assert metrics["shadow_submitted"] >= 1

import asyncio
from unittest.mock import AsyncMock

import httpx
import pytest

from tests.conftest import make_chat_response


class TestChatEndpoint:
    async def test_chat_returns_primary_response(self, client, mock_llm_client):
        response = await client.post(
            "/v1/chat",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        assert response.status_code == 200
        body = response.json()
        assert "choices" in body
        mock_llm_client.chat_completion.assert_called()

    async def test_chat_rejects_streaming(self, client):
        response = await client.post(
            "/v1/chat",
            json={
                "messages": [{"role": "user", "content": "hello"}],
                "stream": True,
            },
        )
        assert response.status_code == 400

    async def test_chat_handles_primary_error(self, test_app, mock_llm_client):
        request = httpx.Request("POST", "http://test/v1/chat/completions")
        response = httpx.Response(429, json={"error": "rate limited"}, request=request)
        mock_llm_client.chat_completion.side_effect = httpx.HTTPStatusError(
            "rate limited", request=request, response=response
        )

        transport = httpx.ASGITransport(app=test_app)
        async with httpx.AsyncClient(transport=transport, base_url="http://test") as ac:
            result = await ac.post(
                "/v1/chat",
                json={"messages": [{"role": "user", "content": "hello"}]},
            )
        assert result.status_code == 429


class TestMetricsEndpoint:
    async def test_metrics_after_request(self, client):
        await client.post(
            "/v1/chat",
            json={"messages": [{"role": "user", "content": "hello"}]},
        )
        await asyncio.sleep(0.3)

        response = await client.get("/metrics")
        assert response.status_code == 200
        metrics = response.json()
        assert metrics["total_requests"] == 1
        assert metrics["shadow_submitted"] == 1
        assert "match_rate_percent" in metrics

    async def test_metrics_initial_state(self, client):
        response = await client.get("/metrics")
        assert response.status_code == 200
        metrics = response.json()
        assert metrics["total_requests"] == 0
        assert metrics["match_rate_percent"] == 0.0


class TestConfigEndpoint:
    async def test_get_config(self, client):
        response = await client.get("/config")
        assert response.status_code == 200
        assert response.json()["shadow_routing_percentage"] == 100.0

    async def test_update_shadow_routing(self, client):
        response = await client.put("/config", json={"shadow_routing_percentage": 50.0})
        assert response.status_code == 200
        assert response.json()["shadow_routing_percentage"] == 50.0

        get_response = await client.get("/config")
        assert get_response.json()["shadow_routing_percentage"] == 50.0

    async def test_update_rejects_invalid_percentage(self, client):
        response = await client.put("/config", json={"shadow_routing_percentage": 150.0})
        assert response.status_code == 422


class TestHealthEndpoint:
    async def test_health(self, client):
        response = await client.get("/health")
        assert response.status_code == 200
        assert response.json()["status"] == "ok"

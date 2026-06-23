from typing import Any
from unittest.mock import AsyncMock

import pytest
from httpx import ASGITransport, AsyncClient

from app.config import RuntimeConfig, Settings
from app.llm_client import LLMClient
from app.main import create_app
from app.metrics import MetricsCollector
from app.shadow_queue import ShadowQueue
from app.trace_store import TraceStore


def make_chat_response(action: str, model: str = "primary") -> dict[str, Any]:
    return {
        "id": "chatcmpl-test",
        "object": "chat.completion",
        "model": model,
        "choices": [
            {
                "index": 0,
                "message": {
                    "role": "assistant",
                    "content": f'{{"action": "{action}"}}',
                },
                "finish_reason": "stop",
            }
        ],
    }


@pytest.fixture
def settings(tmp_path) -> Settings:
    return Settings(
        inference_api_key="test-key",
        primary_model="primary-model",
        candidate_model="candidate-model",
        shadow_queue_max_size=10,
        shadow_max_workers=2,
        shadow_timeout_seconds=5.0,
        shadow_routing_percentage=100.0,
        trace_db_path=str(tmp_path / "test_traces.db"),
        primary_timeout_seconds=10.0,
    )


@pytest.fixture
def metrics() -> MetricsCollector:
    return MetricsCollector()


@pytest.fixture
def runtime_config(settings: Settings) -> RuntimeConfig:
    return RuntimeConfig(settings)


@pytest.fixture
def trace_store(settings: Settings) -> TraceStore:
    return TraceStore(settings.trace_db_path)


@pytest.fixture
def mock_llm_client() -> AsyncMock:
    client = AsyncMock(spec=LLMClient)
    client.chat_completion = AsyncMock()
    return client


@pytest.fixture
async def shadow_queue(
    settings: Settings,
    runtime_config: RuntimeConfig,
    metrics: MetricsCollector,
    trace_store: TraceStore,
    mock_llm_client: AsyncMock,
) -> ShadowQueue:
    queue = ShadowQueue(
        settings, runtime_config, metrics, trace_store, mock_llm_client
    )
    await queue.start()
    yield queue
    await queue.stop()


@pytest.fixture
async def test_app(
    settings: Settings,
    runtime_config: RuntimeConfig,
    metrics: MetricsCollector,
    trace_store: TraceStore,
    mock_llm_client: AsyncMock,
):
    async def primary_side_effect(payload, *, model, timeout=None):
        if model == settings.primary_model:
            return make_chat_response("search", model=model)
        if model == settings.candidate_model:
            return make_chat_response("search", model=model)
        raise ValueError(f"unexpected model: {model}")

    mock_llm_client.chat_completion.side_effect = primary_side_effect

    shadow_queue = ShadowQueue(
        settings, runtime_config, metrics, trace_store, mock_llm_client
    )

    app = create_app(
        settings=settings,
        runtime_config=runtime_config,
        metrics=metrics,
        trace_store=trace_store,
        llm_client=mock_llm_client,
        shadow_queue=shadow_queue,
    )

    async with app.router.lifespan_context(app):
        yield app


@pytest.fixture
async def client(test_app) -> AsyncClient:
    transport = ASGITransport(app=test_app)
    async with AsyncClient(transport=transport, base_url="http://test") as ac:
        yield ac

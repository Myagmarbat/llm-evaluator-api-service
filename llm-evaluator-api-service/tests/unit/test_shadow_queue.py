import asyncio
from unittest.mock import AsyncMock

import httpx
import pytest

from app.config import RuntimeConfig, Settings
from app.metrics import MetricsCollector
from app.shadow_queue import ShadowQueue
from app.trace_store import TraceStore
from tests.conftest import make_chat_response


@pytest.fixture
def small_queue_settings(tmp_path) -> Settings:
    return Settings(
        shadow_queue_max_size=2,
        shadow_max_workers=1,
        shadow_timeout_seconds=1.0,
        shadow_routing_percentage=100.0,
        trace_db_path=str(tmp_path / "shadow_test.db"),
        primary_model="primary",
        candidate_model="candidate",
    )


class TestShadowQueueLoadShedding:
    async def test_drops_when_queue_full(self, small_queue_settings):
        metrics = MetricsCollector()
        runtime_config = RuntimeConfig(small_queue_settings)
        trace_store = TraceStore(small_queue_settings.trace_db_path)

        async def slow_completion(*_args, **_kwargs):
            await asyncio.sleep(10)

        slow_client = AsyncMock()
        slow_client.chat_completion = AsyncMock(side_effect=slow_completion)

        queue = ShadowQueue(
            small_queue_settings, runtime_config, metrics, trace_store, slow_client
        )
        await queue.start()

        payload = {"messages": [{"role": "user", "content": "hi"}]}
        primary = make_chat_response("search")

        # Fill queue (maxsize=2) plus one in-flight worker
        assert queue.try_submit(payload, primary) is True
        assert queue.try_submit(payload, primary) is True

        # Third should be dropped immediately
        dropped_before = metrics.snapshot()["shadow_dropped"]
        # May succeed if worker hasn't picked up yet; keep submitting until drop
        for _ in range(5):
            queue.try_submit(payload, primary)

        assert metrics.snapshot()["shadow_dropped"] > dropped_before
        await queue.stop()

    async def test_routing_percentage_zero_skips_all(self, small_queue_settings):
        small_queue_settings.shadow_routing_percentage = 0
        metrics = MetricsCollector()
        runtime_config = RuntimeConfig(small_queue_settings)
        trace_store = TraceStore(small_queue_settings.trace_db_path)
        client = AsyncMock()

        queue = ShadowQueue(
            small_queue_settings, runtime_config, metrics, trace_store, client
        )
        await queue.start()

        submitted = queue.try_submit({"messages": []}, make_chat_response("x"))
        assert submitted is False
        assert metrics.snapshot()["shadow_submitted"] == 0
        await queue.stop()

    async def test_records_timeout(self, small_queue_settings):
        metrics = MetricsCollector()
        runtime_config = RuntimeConfig(small_queue_settings)
        trace_store = TraceStore(small_queue_settings.trace_db_path)

        client = AsyncMock()
        client.chat_completion = AsyncMock(side_effect=httpx.TimeoutException("timeout"))

        queue = ShadowQueue(
            small_queue_settings, runtime_config, metrics, trace_store, client
        )
        await queue.start()

        queue.try_submit({"messages": []}, make_chat_response("search"))
        await asyncio.sleep(0.3)

        assert metrics.snapshot()["shadow_timeouts"] >= 1
        await queue.stop()

    async def test_records_match(self, small_queue_settings):
        metrics = MetricsCollector()
        runtime_config = RuntimeConfig(small_queue_settings)
        trace_store = TraceStore(small_queue_settings.trace_db_path)

        client = AsyncMock()
        client.chat_completion = AsyncMock(
            return_value=make_chat_response("search", model="candidate")
        )

        queue = ShadowQueue(
            small_queue_settings, runtime_config, metrics, trace_store, client
        )
        await queue.start()

        queue.try_submit({"messages": []}, make_chat_response("search"))
        await asyncio.sleep(0.3)

        snap = metrics.snapshot()
        assert snap["total_comparisons"] >= 1
        assert snap["total_matches"] >= 1
        await queue.stop()

    async def test_records_mismatch_to_sqlite(self, small_queue_settings):
        metrics = MetricsCollector()
        runtime_config = RuntimeConfig(small_queue_settings)
        trace_store = TraceStore(small_queue_settings.trace_db_path)

        client = AsyncMock()
        client.chat_completion = AsyncMock(
            return_value=make_chat_response("book", model="candidate")
        )

        queue = ShadowQueue(
            small_queue_settings, runtime_config, metrics, trace_store, client
        )
        await queue.start()

        queue.try_submit({"messages": []}, make_chat_response("search"))
        await asyncio.sleep(0.3)

        count = await trace_store.count_mismatches()
        assert count >= 1
        await queue.stop()

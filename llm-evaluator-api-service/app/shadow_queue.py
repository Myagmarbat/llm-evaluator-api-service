import asyncio
import logging
import random
from dataclasses import dataclass
from typing import Any

import httpx

from app.config import RuntimeConfig, Settings
from app.evaluator import evaluate_responses
from app.llm_client import LLMClient
from app.metrics import MetricsCollector
from app.trace_store import TraceStore

logger = logging.getLogger(__name__)


@dataclass
class ShadowTask:
    request_payload: dict[str, Any]
    primary_response: dict[str, Any]


class ShadowQueue:
    def __init__(
        self,
        settings: Settings,
        runtime_config: RuntimeConfig,
        metrics: MetricsCollector,
        trace_store: TraceStore,
        llm_client: LLMClient,
    ) -> None:
        self._settings = settings
        self._runtime_config = runtime_config
        self._metrics = metrics
        self._trace_store = trace_store
        self._llm_client = llm_client

        self._queue: asyncio.Queue[ShadowTask | None] = asyncio.Queue(
            maxsize=settings.shadow_queue_max_size
        )
        self._semaphore = asyncio.Semaphore(settings.shadow_max_workers)
        self._active_workers = 0
        self._workers: list[asyncio.Task] = []
        self._started = False

    async def start(self) -> None:
        if self._started:
            return
        self._started = True
        for _ in range(self._settings.shadow_max_workers):
            self._workers.append(asyncio.create_task(self._worker_loop()))

    async def stop(self) -> None:
        if not self._started:
            return
        for _ in self._workers:
            await self._queue.put(None)
        await asyncio.gather(*self._workers, return_exceptions=True)
        self._workers.clear()
        self._started = False

    def try_submit(
        self,
        request_payload: dict[str, Any],
        primary_response: dict[str, Any],
    ) -> bool:
        percentage = self._runtime_config.shadow_routing_percentage
        if percentage <= 0:
            return False
        if percentage < 100 and random.random() * 100 >= percentage:
            return False

        task = ShadowTask(
            request_payload=request_payload,
            primary_response=primary_response,
        )
        try:
            self._queue.put_nowait(task)
        except asyncio.QueueFull:
            self._metrics.increment_shadow_dropped()
            logger.warning("Shadow queue full; shedding background evaluation")
            return False

        self._metrics.increment_shadow_submitted()
        self._metrics.set_queue_depth(self._queue.qsize())
        return True

    async def _worker_loop(self) -> None:
        while True:
            task = await self._queue.get()
            try:
                self._metrics.set_queue_depth(self._queue.qsize())
                if task is None:
                    return
                async with self._semaphore:
                    self._active_workers += 1
                    self._metrics.set_active_workers(self._active_workers)
                    try:
                        await self._process_task(task)
                    finally:
                        self._active_workers -= 1
                        self._metrics.set_active_workers(self._active_workers)
            finally:
                self._queue.task_done()
                self._metrics.set_queue_depth(self._queue.qsize())

    async def _process_task(self, task: ShadowTask) -> None:
        try:
            candidate_response = await self._llm_client.chat_completion(
                task.request_payload,
                model=self._settings.candidate_model,
                timeout=self._settings.shadow_timeout_seconds,
            )
        except httpx.TimeoutException:
            self._metrics.increment_shadow_timeouts()
            logger.warning("Candidate LLM request timed out")
            return
        except Exception:
            self._metrics.increment_shadow_errors()
            logger.exception("Candidate LLM request failed")
            return

        result = evaluate_responses(task.primary_response, candidate_response)
        self._metrics.record_comparison(matched=result.actions_match)

        if not result.actions_match:
            await self._trace_store.record_mismatch(
                request_payload=task.request_payload,
                primary_response=task.primary_response,
                candidate_response=candidate_response,
                evaluation=result.model_dump(),
            )

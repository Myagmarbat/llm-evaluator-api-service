import logging
from contextlib import asynccontextmanager
from typing import Any

import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse

from app.config import RuntimeConfig, Settings, get_runtime_config, get_settings
from app.llm_client import LLMClient
from app.metrics import MetricsCollector
from app.models import ChatRequest, ConfigResponse, ConfigUpdateRequest, MetricsResponse
from app.shadow_queue import ShadowQueue
from app.trace_store import TraceStore

logger = logging.getLogger(__name__)


class AppState:
    def __init__(
        self,
        settings: Settings,
        runtime_config: RuntimeConfig,
        metrics: MetricsCollector,
        trace_store: TraceStore,
        llm_client: LLMClient,
        shadow_queue: ShadowQueue,
    ) -> None:
        self.settings = settings
        self.runtime_config = runtime_config
        self.metrics = metrics
        self.trace_store = trace_store
        self.llm_client = llm_client
        self.shadow_queue = shadow_queue


def create_app(
    settings: Settings | None = None,
    runtime_config: RuntimeConfig | None = None,
    metrics: MetricsCollector | None = None,
    trace_store: TraceStore | None = None,
    llm_client: LLMClient | None = None,
    shadow_queue: ShadowQueue | None = None,
) -> FastAPI:
    settings = settings or get_settings()
    runtime_config = runtime_config or RuntimeConfig(settings)
    metrics = metrics or MetricsCollector()
    trace_store = trace_store or TraceStore(settings.trace_db_path)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        client = llm_client or LLMClient(settings)
        await client.__aenter__()
        queue = shadow_queue or ShadowQueue(
            settings, runtime_config, metrics, trace_store, client
        )
        app.state.app_state = AppState(
            settings, runtime_config, metrics, trace_store, client, queue
        )
        await trace_store.initialize()
        await queue.start()
        try:
            yield
        finally:
            await queue.stop()
            await client.__aexit__(None, None, None)

    app = FastAPI(
        title="Shadow LLM Proxy",
        description="Synchronous primary LLM proxy with asynchronous candidate shadow evaluation",
        version="1.0.0",
        lifespan=lifespan,
    )

    @app.post("/v1/chat")
    async def chat(request: Request) -> JSONResponse:
        state: AppState = app.state.app_state
        state.metrics.increment_requests()

        try:
            body = await request.json()
        except Exception as exc:
            raise HTTPException(status_code=400, detail="Invalid JSON body") from exc

        chat_request = ChatRequest.model_validate(body)
        if chat_request.stream:
            raise HTTPException(status_code=400, detail="Streaming is not supported")

        payload = chat_request.model_dump(exclude_none=True)
        payload.pop("stream", None)

        try:
            primary_response = await state.llm_client.chat_completion(
                payload,
                model=state.settings.primary_model,
            )
        except httpx.HTTPStatusError as exc:
            logger.error("Primary LLM returned error: %s", exc.response.status_code)
            return JSONResponse(
                status_code=exc.response.status_code,
                content=exc.response.json() if exc.response.content else {"error": str(exc)},
            )
        except httpx.TimeoutException as exc:
            raise HTTPException(status_code=504, detail="Primary LLM request timed out") from exc
        except Exception as exc:
            logger.exception("Primary LLM request failed")
            raise HTTPException(status_code=502, detail="Primary LLM request failed") from exc

        # Fire-and-forget shadow evaluation; never blocks the primary response.
        state.shadow_queue.try_submit(payload, primary_response)

        return JSONResponse(content=primary_response)

    @app.get("/metrics", response_model=MetricsResponse)
    async def get_metrics() -> MetricsResponse:
        state: AppState = app.state.app_state
        return MetricsResponse(**state.metrics.snapshot())

    @app.get("/config", response_model=ConfigResponse)
    async def get_config() -> ConfigResponse:
        state: AppState = app.state.app_state
        return ConfigResponse(
            shadow_routing_percentage=state.runtime_config.shadow_routing_percentage,
            shadow_queue_max_size=state.settings.shadow_queue_max_size,
            shadow_max_workers=state.settings.shadow_max_workers,
            shadow_timeout_seconds=state.settings.shadow_timeout_seconds,
        )

    @app.put("/config", response_model=ConfigResponse)
    async def update_config(update: ConfigUpdateRequest) -> ConfigResponse:
        state: AppState = app.state.app_state
        state.runtime_config.set_shadow_routing_percentage(update.shadow_routing_percentage)
        return await get_config()

    @app.get("/health")
    async def health() -> dict[str, str]:
        return {"status": "ok"}

    return app


app = create_app()

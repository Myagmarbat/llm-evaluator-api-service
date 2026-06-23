from typing import Any

from pydantic import BaseModel, Field


class ChatRequest(BaseModel):
    model: str | None = None
    messages: list[dict[str, Any]]
    temperature: float | None = None
    max_tokens: int | None = None
    max_completion_tokens: int | None = None
    stream: bool | None = False

    model_config = {"extra": "allow"}


class MetricsResponse(BaseModel):
    total_requests: int
    shadow_submitted: int
    shadow_dropped: int
    shadow_errors: int
    shadow_timeouts: int
    total_comparisons: int
    total_matches: int
    match_rate_percent: float
    shadow_queue_depth: int
    shadow_active_workers: int


class ConfigUpdateRequest(BaseModel):
    shadow_routing_percentage: float = Field(ge=0, le=100)


class ConfigResponse(BaseModel):
    shadow_routing_percentage: float
    shadow_queue_max_size: int
    shadow_max_workers: int
    shadow_timeout_seconds: float


class EvaluationResult(BaseModel):
    primary_json_valid: bool
    candidate_json_valid: bool
    primary_action: str | None = None
    candidate_action: str | None = None
    actions_match: bool = False

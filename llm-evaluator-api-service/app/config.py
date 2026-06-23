from functools import lru_cache
from threading import Lock

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # Upstream DigitalOcean Serverless Inference
    inference_base_url: str = "https://inference.do-ai.run"
    inference_api_key: str = ""

    primary_model: str = "meta-llama/Meta-Llama-3.1-8B-Instruct"
    candidate_model: str = "meta-llama/Meta-Llama-3.1-8B-Instruct"

    # Shadow execution bounds
    shadow_queue_max_size: int = Field(default=100, ge=1)
    shadow_max_workers: int = Field(default=10, ge=1)
    shadow_timeout_seconds: float = Field(default=30.0, gt=0)
    shadow_routing_percentage: float = Field(default=100.0, ge=0, le=100)

    # SQLite trace store
    trace_db_path: str = "traces.db"

    # HTTP client
    primary_timeout_seconds: float = Field(default=60.0, gt=0)


class RuntimeConfig:
    """Thread-safe runtime configuration for dynamic updates."""

    def __init__(self, settings: Settings) -> None:
        self._lock = Lock()
        self._shadow_routing_percentage = settings.shadow_routing_percentage

    @property
    def shadow_routing_percentage(self) -> float:
        with self._lock:
            return self._shadow_routing_percentage

    def set_shadow_routing_percentage(self, value: float) -> None:
        if not 0 <= value <= 100:
            raise ValueError("shadow_routing_percentage must be between 0 and 100")
        with self._lock:
            self._shadow_routing_percentage = value


@lru_cache
def get_settings() -> Settings:
    return Settings()


def get_runtime_config() -> RuntimeConfig:
    return RuntimeConfig(get_settings())

from dataclasses import dataclass, field
from threading import Lock


@dataclass
class MetricsSnapshot:
    total_requests: int = 0
    shadow_submitted: int = 0
    shadow_dropped: int = 0
    shadow_errors: int = 0
    shadow_timeouts: int = 0
    total_comparisons: int = 0
    total_matches: int = 0


class MetricsCollector:
    """Thread-safe in-memory metrics for shadow evaluation."""

    def __init__(self) -> None:
        self._lock = Lock()
        self._snapshot = MetricsSnapshot()
        self._queue_depth = 0
        self._active_workers = 0

    def increment_requests(self) -> None:
        with self._lock:
            self._snapshot.total_requests += 1

    def increment_shadow_submitted(self) -> None:
        with self._lock:
            self._snapshot.shadow_submitted += 1

    def increment_shadow_dropped(self) -> None:
        with self._lock:
            self._snapshot.shadow_dropped += 1

    def increment_shadow_errors(self) -> None:
        with self._lock:
            self._snapshot.shadow_errors += 1

    def increment_shadow_timeouts(self) -> None:
        with self._lock:
            self._snapshot.shadow_timeouts += 1

    def record_comparison(self, *, matched: bool) -> None:
        with self._lock:
            self._snapshot.total_comparisons += 1
            if matched:
                self._snapshot.total_matches += 1

    def set_queue_depth(self, depth: int) -> None:
        with self._lock:
            self._queue_depth = depth

    def set_active_workers(self, count: int) -> None:
        with self._lock:
            self._active_workers = count

    def snapshot(self) -> dict:
        with self._lock:
            comparisons = self._snapshot.total_comparisons
            matches = self._snapshot.total_matches
            match_rate = (matches / comparisons * 100.0) if comparisons > 0 else 0.0
            return {
                "total_requests": self._snapshot.total_requests,
                "shadow_submitted": self._snapshot.shadow_submitted,
                "shadow_dropped": self._snapshot.shadow_dropped,
                "shadow_errors": self._snapshot.shadow_errors,
                "shadow_timeouts": self._snapshot.shadow_timeouts,
                "total_comparisons": comparisons,
                "total_matches": matches,
                "match_rate_percent": round(match_rate, 2),
                "shadow_queue_depth": self._queue_depth,
                "shadow_active_workers": self._active_workers,
            }

    def reset(self) -> None:
        with self._lock:
            self._snapshot = MetricsSnapshot()
            self._queue_depth = 0
            self._active_workers = 0

import pytest

from app.metrics import MetricsCollector


class TestMetricsCollector:
    def test_initial_snapshot(self):
        metrics = MetricsCollector()
        snap = metrics.snapshot()
        assert snap["total_requests"] == 0
        assert snap["match_rate_percent"] == 0.0

    def test_match_rate_calculation(self):
        metrics = MetricsCollector()
        metrics.record_comparison(matched=True)
        metrics.record_comparison(matched=True)
        metrics.record_comparison(matched=False)

        snap = metrics.snapshot()
        assert snap["total_comparisons"] == 3
        assert snap["total_matches"] == 2
        assert snap["match_rate_percent"] == pytest.approx(66.67, rel=0.01)

    def test_counters(self):
        metrics = MetricsCollector()
        metrics.increment_requests()
        metrics.increment_shadow_submitted()
        metrics.increment_shadow_dropped()
        metrics.increment_shadow_errors()
        metrics.increment_shadow_timeouts()

        snap = metrics.snapshot()
        assert snap["total_requests"] == 1
        assert snap["shadow_submitted"] == 1
        assert snap["shadow_dropped"] == 1
        assert snap["shadow_errors"] == 1
        assert snap["shadow_timeouts"] == 1

    def test_reset(self):
        metrics = MetricsCollector()
        metrics.increment_requests()
        metrics.reset()
        assert metrics.snapshot()["total_requests"] == 0

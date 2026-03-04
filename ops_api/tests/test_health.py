from __future__ import annotations

from collections.abc import Iterator

from fastapi.testclient import TestClient

from app.db.session import get_db
from app.main import app


class _FakeDb:
    def execute(self, _statement):
        return 1


def _override_db() -> Iterator[_FakeDb]:
    yield _FakeDb()


def test_health_endpoint_reports_up_with_overridden_db():
    app.dependency_overrides[get_db] = _override_db
    try:
        with TestClient(app) as client:
            res = client.get("/health")
    finally:
        app.dependency_overrides.clear()

    assert res.status_code == 200, res.text
    data = res.json()
    assert data["api"] == "up"
    # /health is sanitized — no internal details like db_latency_ms or environment
    assert "status" in data
    assert "db_latency_ms" not in data
    assert "environment" not in data


def test_core_routes_are_registered():
    route_paths = {route.path for route in app.routes}
    assert "/health" in route_paths
    assert "/auth/login" in route_paths
    assert "/cases" in route_paths
    assert "/models" in route_paths

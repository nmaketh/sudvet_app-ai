from __future__ import annotations

import uuid

from tests.conftest import token_headers


def _register_payload() -> dict[str, str]:
    suffix = uuid.uuid4().hex[:10]
    return {
        "name": "New Field User",
        "email": f"user-{suffix}@example.com",
        "password": "Test1234!",
    }


def test_register_requires_authentication(app_client):
    res = app_client.post("/auth/register", json=_register_payload())
    assert res.status_code == 401, res.text


def test_register_rejects_non_admin(app_client, cahw_user):
    res = app_client.post(
        "/auth/register",
        headers=token_headers(cahw_user),
        json=_register_payload(),
    )
    assert res.status_code == 403, res.text


def test_register_allows_admin(app_client, admin_user):
    payload = _register_payload()
    res = app_client.post(
        "/auth/register",
        headers=token_headers(admin_user),
        json=payload,
    )
    assert res.status_code == 200, res.text
    data = res.json()
    assert data["email"] == payload["email"]
    assert data["role"] == "CAHW"

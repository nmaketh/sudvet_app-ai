from __future__ import annotations

import sqlite3

from app import db as db_module


def test_health_endpoint_returns_metadata(client):
    res = client.get("/health")
    assert res.status_code == 200
    payload = res.json()
    assert payload["status"] == "ok"
    assert payload["service"] == "cattle-backend"
    assert "version" in payload
    assert "environment" in payload


def test_signup_verify_and_login_flow(client):
    register_payload = {
        "name": "Test User",
        "email": "test.user@example.com",
        "password": "Password123!",
    }
    register_res = client.post("/auth/register", json=register_payload)
    assert register_res.status_code == 200, register_res.text
    register_data = register_res.json()
    assert register_data["otpRequired"] is True
    signup_token = register_data["signupToken"]

    with sqlite3.connect(db_module.DB_PATH) as conn:
        row = conn.execute(
            "SELECT otp_code FROM signup_otps WHERE signup_token = ?",
            (signup_token,),
        ).fetchone()
    assert row is not None
    otp = row[0]

    verify_res = client.post(
        "/auth/signup/verify",
        json={"signupToken": signup_token, "otp": otp},
    )
    assert verify_res.status_code == 200, verify_res.text
    verify_data = verify_res.json()
    assert verify_data.get("token")
    assert verify_data.get("refreshToken")
    assert verify_data["user"]["email"] == "test.user@example.com"

    login_res = client.post(
        "/auth/login",
        json={"email": "test.user@example.com", "password": "Password123!"},
    )
    assert login_res.status_code == 200, login_res.text
    login_data = login_res.json()
    assert login_data.get("token")
    assert login_data["user"]["email"] == "test.user@example.com"

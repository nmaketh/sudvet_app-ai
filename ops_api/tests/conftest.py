from __future__ import annotations

import os
import uuid
from datetime import datetime, timezone
from pathlib import Path
import sys

OPS_API_ROOT = Path(__file__).resolve().parents[1]
if str(OPS_API_ROOT) not in sys.path:
    sys.path.insert(0, str(OPS_API_ROOT))

# Local tests default to SQLite to avoid requiring PostgreSQL client drivers
# during import-time engine creation in environments without psycopg2 wheels.
os.environ.setdefault("DATABASE_URL", "sqlite:///./ops_api_test.db")
# Disable Supabase storage — image upload is not exercised in unit/integration tests
os.environ.setdefault("SUPABASE_URL", "")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "")

import pytest
from fastapi.testclient import TestClient


# ── App-level fixtures (imported after env vars are set) ──────────────────────

@pytest.fixture(scope="session")
def app_client():
    """Session-scoped HTTP test client. Startup events run once (creates tables)."""
    from app.main import app
    from app.models.models import Base
    from app.db.session import engine
    Base.metadata.create_all(bind=engine)
    with TestClient(app, raise_server_exceptions=True) as c:
        yield c


@pytest.fixture(scope="session")
def db_session():
    """Session-scoped DB session shared across all integration tests."""
    from app.db.session import SessionLocal
    session = SessionLocal()
    yield session
    session.close()


# ── Helpers ───────────────────────────────────────────────────────────────────

def _make_user(db, *, name: str, email: str, role: str):
    """Return existing or create a new User in the test DB."""
    from app.models.models import User, UserRole
    from app.core.security import get_password_hash
    existing = db.query(User).filter(User.email == email).first()
    if existing:
        return existing
    user = User(
        name=name,
        email=email,
        password_hash=get_password_hash("Test1234!"),
        role=UserRole(role),
        created_at=datetime.now(timezone.utc),
    )
    db.add(user)
    db.commit()
    db.refresh(user)
    return user


def make_case(db, *, submitted_by_user_id: int,
              triage_status: str = "escalated",
              assigned_to_user_id=None,
              requested_vet_id=None):
    """Create a minimal Case row and return it."""
    from app.models.models import Case, TriageStatus, CaseStatus, RiskLevel
    case = Case(
        id=str(uuid.uuid4()),
        submitted_by_user_id=submitted_by_user_id,
        created_at=datetime.now(timezone.utc),
        symptoms_json={},
        prediction_json={"label": "normal", "confidence": 0.9},
        method="bayesian",
        confidence=0.9,
        risk_level=RiskLevel.low,
        status=CaseStatus.open,
        triage_status=TriageStatus(triage_status),
        assigned_to_user_id=assigned_to_user_id,
        requested_vet_id=requested_vet_id,
        urgent=False,
    )
    db.add(case)
    db.commit()
    db.refresh(case)
    return case


def token_headers(user) -> dict:
    from app.core.security import create_access_token
    tok = create_access_token(subject=str(user.id), role=user.role.value)
    return {"Authorization": f"Bearer {tok}"}


# ── User fixtures (session-scoped — created once, reused) ─────────────────────

@pytest.fixture(scope="session")
def admin_user(db_session):
    return _make_user(db_session, name="Admin", email="admin@test.local", role="ADMIN")


@pytest.fixture(scope="session")
def vet_a(db_session):
    return _make_user(db_session, name="Vet A", email="veta@test.local", role="VET")


@pytest.fixture(scope="session")
def vet_b(db_session):
    return _make_user(db_session, name="Vet B", email="vetb@test.local", role="VET")


@pytest.fixture(scope="session")
def cahw_user(db_session):
    return _make_user(db_session, name="CAHW", email="cahw@test.local", role="CAHW")

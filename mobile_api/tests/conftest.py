from __future__ import annotations

from pathlib import Path
import sys

import pytest
from fastapi.testclient import TestClient

MOBILE_API_ROOT = Path(__file__).resolve().parents[1]
if str(MOBILE_API_ROOT) not in sys.path:
    sys.path.insert(0, str(MOBILE_API_ROOT))

from app import db as db_module
from app.main import app


@pytest.fixture()
def client(tmp_path: Path):
    original_db_path = db_module.DB_PATH
    db_module.DB_PATH = tmp_path / "mobile_api_test.db"
    try:
        with TestClient(app) as test_client:
            yield test_client
    finally:
        db_module.DB_PATH = original_db_path

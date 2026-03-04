from __future__ import annotations

import sqlite3
from contextlib import contextmanager
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DB_PATH = ROOT / "cattle_backend.db"

@contextmanager
def db_conn() -> sqlite3.Connection:
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        yield conn
        conn.commit()
    finally:
        conn.close()


def init_db() -> None:
    with db_conn() as conn:
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users(
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              created_at TEXT NOT NULL
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS auth_tokens(
              token TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              expires_at TEXT,
              FOREIGN KEY(user_id) REFERENCES users(id)
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS auth_refresh_tokens(
              token TEXT PRIMARY KEY,
              user_id TEXT NOT NULL,
              created_at TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              revoked_at TEXT,
              FOREIGN KEY(user_id) REFERENCES users(id)
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS signup_otps(
              signup_token TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              email TEXT NOT NULL UNIQUE,
              password_hash TEXT NOT NULL,
              otp_code TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              created_at TEXT NOT NULL,
              attempt_count INTEGER NOT NULL DEFAULT 0,
              resend_count INTEGER NOT NULL DEFAULT 0,
              last_sent_at TEXT NOT NULL,
              locked_until TEXT
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS otp_rate_limits(
              email TEXT PRIMARY KEY,
              window_start TEXT NOT NULL,
              request_count INTEGER NOT NULL DEFAULT 0
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS password_reset_otps(
              reset_token TEXT PRIMARY KEY,
              email TEXT NOT NULL UNIQUE,
              otp_code TEXT NOT NULL,
              expires_at TEXT NOT NULL,
              created_at TEXT NOT NULL,
              attempt_count INTEGER NOT NULL DEFAULT 0,
              resend_count INTEGER NOT NULL DEFAULT 0,
              last_sent_at TEXT NOT NULL,
              locked_until TEXT
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS animals(
              id TEXT PRIMARY KEY,
              userId TEXT,
              tag TEXT NOT NULL UNIQUE,
              name TEXT,
              dob TEXT,
              location TEXT,
              notes TEXT,
              createdAt TEXT NOT NULL
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS cases(
              id TEXT PRIMARY KEY,
              userId TEXT,
              animalId TEXT,
              animalName TEXT,
              animalTag TEXT,
              createdAt TEXT NOT NULL,
              imagePath TEXT,
              symptomsJson TEXT NOT NULL,
              status TEXT NOT NULL,
              predictionJson TEXT,
              followUpStatus TEXT NOT NULL,
              followUpDate TEXT,
              notes TEXT,
              syncedAt TEXT,
              temperature REAL,
              severity REAL,
              attachmentsJson TEXT,
              FOREIGN KEY(animalId) REFERENCES animals(id)
            );
            """
        )
        conn.execute(
            """
            CREATE TABLE IF NOT EXISTS background_jobs(
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              payload_json TEXT NOT NULL,
              status TEXT NOT NULL,
              error_message TEXT,
              created_at TEXT NOT NULL,
              started_at TEXT,
              finished_at TEXT
            );
            """
        )
        _ensure_column(conn, "signup_otps", "attempt_count", "INTEGER NOT NULL DEFAULT 0")
        _ensure_column(conn, "signup_otps", "resend_count", "INTEGER NOT NULL DEFAULT 0")
        _ensure_column(conn, "signup_otps", "last_sent_at", "TEXT")
        _ensure_column(conn, "signup_otps", "locked_until", "TEXT")
        conn.execute("UPDATE signup_otps SET last_sent_at = created_at WHERE last_sent_at IS NULL")
        _ensure_column(conn, "animals", "userId", "TEXT")
        _ensure_column(conn, "cases", "userId", "TEXT")
        _ensure_column(
            conn,
            "password_reset_otps",
            "attempt_count",
            "INTEGER NOT NULL DEFAULT 0",
        )
        _ensure_column(
            conn,
            "password_reset_otps",
            "resend_count",
            "INTEGER NOT NULL DEFAULT 0",
        )
        _ensure_column(conn, "password_reset_otps", "last_sent_at", "TEXT")
        _ensure_column(conn, "password_reset_otps", "locked_until", "TEXT")
        conn.execute(
            "UPDATE password_reset_otps SET last_sent_at = created_at WHERE last_sent_at IS NULL"
        )
        _ensure_column(conn, "auth_tokens", "expires_at", "TEXT")


def _ensure_column(conn: sqlite3.Connection, table: str, column: str, ddl: str) -> None:
    info = conn.execute(f"PRAGMA table_info({table})").fetchall()
    columns = {row["name"] for row in info}
    if column in columns:
        return
    conn.execute(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}")

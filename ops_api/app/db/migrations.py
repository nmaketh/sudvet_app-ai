"""
Startup migrations - run once at application boot.

Handles:
1. Adding new columns that Base.metadata.create_all() won't add to existing tables.
2. Converting legacy triage_status values to the current two-value schema:
     'new'      -> 'escalated'   (was "not yet reviewed"; now all cases are visible)
     'assigned' -> 'needs_review' (ownership is tracked via assigned_to_user_id FK)
"""
import logging

from sqlalchemy import inspect, text
from sqlalchemy.orm import Session

log = logging.getLogger(__name__)


def _dialect_name(session: Session) -> str:
    bind = session.get_bind()
    return bind.dialect.name if bind is not None else ""


def _column_exists(session: Session, table: str, column: str) -> bool:
    """Check if a column exists in a table across supported SQL dialects."""
    bind = session.get_bind()
    if bind is None:
        return False

    inspector = inspect(bind)
    try:
        columns = inspector.get_columns(table)
    except Exception:
        return False

    return any(col.get("name") == column for col in columns)


def run_migrations(session: Session) -> None:
    """Idempotent migration runner. Safe to call on every startup."""
    _add_column_if_missing(session, "cases", "requested_vet_id", "INTEGER REFERENCES users(id)")
    _add_column_if_missing(session, "cases", "request_note", "TEXT")
    _migrate_triage_status(session)
    session.commit()
    log.info("DB migrations completed.")


def _add_column_if_missing(session: Session, table: str, column: str, definition: str) -> None:
    if _column_exists(session, table, column):
        return

    if _dialect_name(session) == "postgresql":
        session.execute(text(f"ALTER TABLE {table} ADD COLUMN IF NOT EXISTS {column} {definition}"))
    else:
        session.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {definition}"))
    log.info("Added column %s.%s", table, column)


def _migrate_triage_status(session: Session) -> None:
    """Convert legacy triage_status values to the current two-value schema."""
    if _dialect_name(session) == "postgresql":
        where_new = "CAST(triage_status AS TEXT) = 'new'"
        where_assigned = "CAST(triage_status AS TEXT) = 'assigned'"
    else:
        where_new = "triage_status = 'new'"
        where_assigned = "triage_status = 'assigned'"

    # 'new' -> 'escalated': these were unreviewed cases; now they're immediately in the vet queue.
    result = session.execute(
        text(f"UPDATE cases SET triage_status = 'escalated' WHERE {where_new}")
    )
    if result.rowcount:
        log.info("Migrated %d cases: triage_status 'new' -> 'escalated'", result.rowcount)

    # 'assigned' -> 'needs_review': ownership is now expressed via assigned_to_user_id only.
    result = session.execute(
        text(f"UPDATE cases SET triage_status = 'needs_review' WHERE {where_assigned}")
    )
    if result.rowcount:
        log.info("Migrated %d cases: triage_status 'assigned' -> 'needs_review'", result.rowcount)

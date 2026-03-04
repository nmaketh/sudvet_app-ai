"""add requested_vet_id, request_note columns and supporting indexes to cases

Revision ID: 0006_requested_vet_fields
Revises: 0005_password_reset_otps
Create Date: 2026-03-02

Notes:
  - Columns may already exist if the startup runtime migration (db/migrations.py) ran first.
    All DDL is guarded with existence checks so this migration is always idempotent.
  - Indexes are created with IF NOT EXISTS to avoid errors on re-runs.
"""

import sqlalchemy as sa
from alembic import op

revision = "0006_requested_vet_fields"
down_revision = "0005_password_reset_otps"
branch_labels = None
depends_on = None


def upgrade() -> None:
    bind = op.get_bind()
    inspector = sa.inspect(bind)
    is_pg = bind.dialect.name == "postgresql"
    existing_cols = {c["name"] for c in inspector.get_columns("cases")}

    # ── Columns ───────────────────────────────────────────────────────────────
    if "requested_vet_id" not in existing_cols:
        op.add_column(
            "cases",
            sa.Column("requested_vet_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        )

    if "request_note" not in existing_cols:
        op.add_column("cases", sa.Column("request_note", sa.Text(), nullable=True))

    # ── Indexes ───────────────────────────────────────────────────────────────
    if is_pg:
        # PostgreSQL supports IF NOT EXISTS natively
        op.execute(
            "CREATE INDEX IF NOT EXISTS ix_cases_assigned_to_user_id"
            " ON cases (assigned_to_user_id)"
        )
        op.execute(
            "CREATE INDEX IF NOT EXISTS ix_cases_requested_vet_id"
            " ON cases (requested_vet_id)"
        )
        op.execute(
            "CREATE INDEX IF NOT EXISTS ix_cases_triage_assigned"
            " ON cases (triage_status, assigned_to_user_id)"
        )
    else:
        existing_indexes = {idx["name"] for idx in inspector.get_indexes("cases")}
        if "ix_cases_assigned_to_user_id" not in existing_indexes:
            op.create_index("ix_cases_assigned_to_user_id", "cases", ["assigned_to_user_id"])
        if "ix_cases_requested_vet_id" not in existing_indexes:
            op.create_index("ix_cases_requested_vet_id", "cases", ["requested_vet_id"])
        if "ix_cases_triage_assigned" not in existing_indexes:
            op.create_index(
                "ix_cases_triage_assigned", "cases", ["triage_status", "assigned_to_user_id"]
            )


def downgrade() -> None:
    bind = op.get_bind()
    is_pg = bind.dialect.name == "postgresql"

    if is_pg:
        op.execute("DROP INDEX IF EXISTS ix_cases_triage_assigned")
        op.execute("DROP INDEX IF EXISTS ix_cases_requested_vet_id")
        op.execute("DROP INDEX IF EXISTS ix_cases_assigned_to_user_id")
    else:
        op.drop_index("ix_cases_triage_assigned", "cases")
        op.drop_index("ix_cases_requested_vet_id", "cases")
        op.drop_index("ix_cases_assigned_to_user_id", "cases")

    op.drop_column("cases", "request_note")
    op.drop_column("cases", "requested_vet_id")

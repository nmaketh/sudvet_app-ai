"""add case workflow lifecycle fields

Revision ID: 0003_case_workflow_fields
Revises: 0002_app_settings
Create Date: 2026-02-27
"""

from alembic import op
import sqlalchemy as sa


revision = "0003_case_workflow_fields"
down_revision = "0002_app_settings"
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Boolean flag set by CAHW at submission; auto-set for high-risk predictions
    op.add_column("cases", sa.Column("urgent", sa.Boolean(), nullable=False, server_default="false"))

    # SLA timestamps — set automatically at each workflow transition
    op.add_column("cases", sa.Column("triaged_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("cases", sa.Column("accepted_at", sa.DateTime(timezone=True), nullable=True))
    op.add_column("cases", sa.Column("resolved_at", sa.DateTime(timezone=True), nullable=True))

    # Structured clinical review submitted by the assigned vet
    op.add_column("cases", sa.Column("vet_review_json", sa.JSON(), nullable=True))

    # Most recent rejection reason when VET returns case to dispatch queue
    op.add_column("cases", sa.Column("rejection_reason", sa.Text(), nullable=True))


def downgrade() -> None:
    op.drop_column("cases", "rejection_reason")
    op.drop_column("cases", "vet_review_json")
    op.drop_column("cases", "resolved_at")
    op.drop_column("cases", "accepted_at")
    op.drop_column("cases", "triaged_at")
    op.drop_column("cases", "urgent")

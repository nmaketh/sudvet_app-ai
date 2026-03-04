"""initial schema

Revision ID: 0001_initial
Revises:
Create Date: 2026-02-25
"""

from alembic import op
import sqlalchemy as sa


revision = "0001_initial"
down_revision = None
branch_labels = None
depends_on = None


user_role = sa.Enum("CAHW", "VET", "ADMIN", name="userrole")
case_status = sa.Enum("open", "in_treatment", "resolved", name="casestatus")
triage_status = sa.Enum("new", "needs_review", "assigned", "escalated", name="triagestatus")
risk_level = sa.Enum("low", "medium", "high", name="risklevel")


def upgrade() -> None:
    user_role.create(op.get_bind(), checkfirst=True)
    case_status.create(op.get_bind(), checkfirst=True)
    triage_status.create(op.get_bind(), checkfirst=True)
    risk_level.create(op.get_bind(), checkfirst=True)

    op.create_table(
        "users",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("name", sa.String(120), nullable=False),
        sa.Column("email", sa.String(255), nullable=False, unique=True),
        sa.Column("password_hash", sa.String(255), nullable=False),
        sa.Column("role", user_role, nullable=False),
        sa.Column("location", sa.String(255), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "animals",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("tag", sa.String(60), nullable=False, unique=True),
        sa.Column("name", sa.String(120), nullable=True),
        sa.Column("owner_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("location", sa.String(255), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "cases",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("client_case_id", sa.String(80), nullable=True),
        sa.Column("animal_id", sa.String(36), sa.ForeignKey("animals.id"), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("submitted_by_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("image_url", sa.String(500), nullable=True),
        sa.Column("symptoms_json", sa.JSON(), nullable=False),
        sa.Column("prediction_json", sa.JSON(), nullable=False),
        sa.Column("method", sa.String(80), nullable=True),
        sa.Column("confidence", sa.Float(), nullable=True),
        sa.Column("risk_level", risk_level, nullable=False),
        sa.Column("status", case_status, nullable=False),
        sa.Column("triage_status", triage_status, nullable=False),
        sa.Column("assigned_to_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=True),
        sa.Column("followup_date", sa.DateTime(timezone=True), nullable=True),
        sa.Column("notes", sa.Text(), nullable=True),
        sa.Column("corrected_label", sa.String(120), nullable=True),
    )

    op.create_table(
        "feedback",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("case_id", sa.String(36), sa.ForeignKey("cases.id"), nullable=False),
        sa.Column("user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("was_correct", sa.Boolean(), nullable=False),
        sa.Column("corrected_label", sa.String(120), nullable=True),
        sa.Column("comment", sa.Text(), nullable=True),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "models",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("type", sa.String(80), nullable=False),
        sa.Column("version", sa.String(80), nullable=False),
        sa.Column("metrics_json", sa.JSON(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "case_events",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("case_id", sa.String(36), sa.ForeignKey("cases.id"), nullable=False),
        sa.Column("actor_user_id", sa.Integer(), sa.ForeignKey("users.id"), nullable=False),
        sa.Column("event_type", sa.String(80), nullable=False),
        sa.Column("payload_json", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )

    op.create_table(
        "error_logs",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("source", sa.String(120), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False),
    )


def downgrade() -> None:
    op.drop_table("error_logs")
    op.drop_table("case_events")
    op.drop_table("models")
    op.drop_table("feedback")
    op.drop_table("cases")
    op.drop_table("animals")
    op.drop_table("users")
    risk_level.drop(op.get_bind(), checkfirst=True)
    triage_status.drop(op.get_bind(), checkfirst=True)
    case_status.drop(op.get_bind(), checkfirst=True)
    user_role.drop(op.get_bind(), checkfirst=True)

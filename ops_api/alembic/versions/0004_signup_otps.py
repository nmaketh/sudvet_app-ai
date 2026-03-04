"""add signup_otps table for email OTP registration flow

Revision ID: 0004_signup_otps
Revises: 0003_case_workflow_fields
Create Date: 2026-02-27
"""

from alembic import op
import sqlalchemy as sa


revision = "0004_signup_otps"
down_revision = "0003_case_workflow_fields"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "signup_otps",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("signup_token", sa.String(36), nullable=False, unique=True),
        sa.Column("name", sa.String(255), nullable=False),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("otp_code", sa.String(6), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("resend_count", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_signup_otps_email", "signup_otps", ["email"])
    op.create_index("ix_signup_otps_signup_token", "signup_otps", ["signup_token"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_signup_otps_signup_token", "signup_otps")
    op.drop_index("ix_signup_otps_email", "signup_otps")
    op.drop_table("signup_otps")

"""add password_reset_otps table

Revision ID: 0005_password_reset_otps
Revises: 0004_signup_otps
Create Date: 2026-03-02
"""

from alembic import op
import sqlalchemy as sa


revision = "0005_password_reset_otps"
down_revision = "0004_signup_otps"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "password_reset_otps",
        sa.Column("id", sa.String(36), primary_key=True),
        sa.Column("reset_token", sa.String(36), nullable=False, unique=True),
        sa.Column("email", sa.String(255), nullable=False),
        sa.Column("otp_code", sa.String(6), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()),
        sa.Column("used", sa.Boolean(), nullable=False, server_default="false"),
    )
    op.create_index("ix_password_reset_otps_email", "password_reset_otps", ["email"])
    op.create_index("ix_password_reset_otps_reset_token", "password_reset_otps", ["reset_token"], unique=True)


def downgrade() -> None:
    op.drop_index("ix_password_reset_otps_reset_token", "password_reset_otps")
    op.drop_index("ix_password_reset_otps_email", "password_reset_otps")
    op.drop_table("password_reset_otps")

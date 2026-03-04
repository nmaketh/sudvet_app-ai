"""
Supabase client singleton for Storage operations.

Usage:
    from app.core.supabase_client import upload_image

    public_url = upload_image(filename, image_bytes, content_type)
"""
from __future__ import annotations

from supabase import Client, create_client

from app.core.config import settings

_client: Client | None = None


def get_supabase() -> Client:
    """Return a cached Supabase client, creating it on first call."""
    global _client
    if _client is None:
        if not settings.supabase_url or not settings.supabase_service_role_key:
            raise RuntimeError(
                "Supabase is not configured. "
                "Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY environment variables."
            )
        _client = create_client(settings.supabase_url, settings.supabase_service_role_key)
    return _client


def upload_image(filename: str, image_bytes: bytes, content_type: str) -> str:
    """Upload image bytes to Supabase Storage and return the public URL.

    Args:
        filename: Target filename in the bucket (e.g. "abc123.jpg").
        image_bytes: Raw image data.
        content_type: MIME type (e.g. "image/jpeg").

    Returns:
        Public URL string for the uploaded file.
    """
    client = get_supabase()
    bucket = settings.supabase_storage_bucket
    client.storage.from_(bucket).upload(
        path=filename,
        file=image_bytes,
        file_options={"content-type": content_type},
    )
    return client.storage.from_(bucket).get_public_url(filename)

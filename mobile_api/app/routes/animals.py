from __future__ import annotations

import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Query

from app.db import db_conn
from app.schemas import AnimalCreateRequest
from app.security import _new_tag, get_current_user, now_iso

router = APIRouter(tags=['animals'])

@router.get("/animals")
def list_animals(
    query: str = Query(default=""),
    current_user: dict[str, Any] = Depends(get_current_user),
) -> list[dict[str, Any]]:
    normalized = query.strip().lower()
    user_id = current_user["id"]
    with db_conn() as conn:
        if normalized:
            rows = conn.execute(
                """
                SELECT id, tag, name, dob, location, notes, createdAt
                FROM animals
                WHERE userId = ?
                  AND (
                    LOWER(COALESCE(name, '')) LIKE ?
                    OR LOWER(tag) LIKE ?
                    OR LOWER(COALESCE(location, '')) LIKE ?
                  )
                ORDER BY createdAt DESC
                """,
                (user_id, f"%{normalized}%", f"%{normalized}%", f"%{normalized}%"),
            ).fetchall()
        else:
            rows = conn.execute(
                """
                SELECT id, tag, name, dob, location, notes, createdAt
                FROM animals
                WHERE userId = ?
                ORDER BY createdAt DESC
                """,
                (user_id,),
            ).fetchall()
    return [dict(row) for row in rows]


@router.get("/animals/{animal_id}")
def get_animal(
    animal_id: str,
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        row = conn.execute(
            """
            SELECT id, tag, name, dob, location, notes, createdAt
            FROM animals
            WHERE id = ? AND userId = ?
            """,
            (animal_id, user_id),
        ).fetchone()
        if row is None:
            raise HTTPException(status_code=404, detail="Animal not found.")
    return dict(row)


@router.post("/animals")
def create_animal(
    payload: AnimalCreateRequest,
    current_user: dict[str, Any] = Depends(get_current_user),
) -> dict[str, Any]:
    user_id = current_user["id"]
    with db_conn() as conn:
        animal_id = str(uuid.uuid4())
        tag = _new_tag()
        while conn.execute("SELECT id FROM animals WHERE tag = ?", (tag,)).fetchone() is not None:
            tag = _new_tag()

        created_at = now_iso()
        conn.execute(
            """
            INSERT INTO animals(id, userId, tag, name, dob, location, notes, createdAt)
            VALUES(?,?,?,?,?,?,?,?)
            """,
            (
                animal_id,
                user_id,
                tag,
                payload.name.strip() if payload.name else None,
                payload.dob,
                payload.location.strip() if payload.location else None,
                payload.notes.strip() if payload.notes else None,
                created_at,
            ),
        )
    return {
        "id": animal_id,
        "tag": tag,
        "name": payload.name.strip() if payload.name else None,
        "dob": payload.dob,
        "location": payload.location.strip() if payload.location else None,
        "notes": payload.notes.strip() if payload.notes else None,
        "createdAt": created_at,
    }

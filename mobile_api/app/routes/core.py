from __future__ import annotations

from typing import Any

from fastapi import APIRouter

from app.inference import _predict_with_external_service
from app.schemas import PredictRequest
from app.security import now_iso
from app.settings import APP_ENV, APP_VERSION

router = APIRouter(tags=['core'])

@router.get("/health")
def health() -> dict[str, Any]:
    return {
        "status": "ok",
        "service": "cattle-backend",
        "version": APP_VERSION,
        "environment": APP_ENV,
        "time": now_iso(),
    }


@router.post("/predict")
def predict(payload: PredictRequest) -> dict[str, Any]:
    return _predict_with_external_service(
        symptoms=payload.symptoms,
        temperature=payload.temperature,
        image_path=payload.imagePath,
        animal_id=payload.animalId,
    )

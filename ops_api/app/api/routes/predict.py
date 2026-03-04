"""
POST /predict/full
Multipart endpoint: accepts symptom JSON payload + optional image file.

Primary path  — cattle_disease_ml microservice (http://ml:8000):
  - Real MobileNetV2 CNN for Normal / LSD / FMD image classification
  - Real Random Forest (RF) symptom classifier (24-feature space)
  - Clinical rules engine for ECF / CBPP
  - Multi-modal fusion logic (image + symptom + rules)

Fallback path — local Bayesian engine (api/app/ml/):
  - Naive Bayes log-likelihood with symptom probability matrix
  - Used automatically when ML service is unavailable or not configured

Flutter symptom names (19) are mapped → RF features (24) AND kept as-is
for the rules engine, so both paths receive maximum signal.
"""

import json
import logging
import os
import uuid
from datetime import datetime
from typing import Optional
from urllib.parse import quote

import httpx
from fastapi import APIRouter, Depends, File, Form, HTTPException, UploadFile
from sqlalchemy.orm import Session

from app.core.config import settings
from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.ml.disease_rules import DISEASE_RECOMMENDATIONS
from app.ml.explainer import explain as bayesian_explain
from app.ml.predictor import predict as bayesian_predict
from app.models.models import User

log = logging.getLogger(__name__)
router = APIRouter(tags=["predict"])

_ALLOWED_IMAGE_TYPES = {"image/jpeg", "image/png", "image/webp", "image/gif"}
_MAX_IMAGE_BYTES = 10 * 1024 * 1024  # 10 MB

# ── Disease helpers ───────────────────────────────────────────────────────────
_DISPLAY = {
    "lsd":    "Lumpy Skin Disease",
    "fmd":    "Foot & Mouth Disease",
    "ecf":    "East Coast Fever",
    "cbpp":   "Contagious Bovine Pleuropneumonia",
    "normal": "No Disease Detected",
}
_DISPLAY_UPPER = {k.upper(): v for k, v in _DISPLAY.items()}
_RECS = DISEASE_RECOMMENDATIONS

# ── Flutter → ML symptom feature mapping ────────────────────────────────────
#
# The RF model uses 24 features from training data (symptom_features.json).
# Flutter sends 19 clinical symptoms with different names.
#
# Strategy:
#   1. Map Flutter names → RF feature names (gives the RF classifier signal)
#   2. Pass original Flutter names too so the clinical rules engine (ECF/CBPP)
#      receives "fever", "swollen_lymph_nodes", "coughing", etc. directly.
#
_FLUTTER_TO_RF: dict[str, list[str]] = {
    # ── Direct / near-direct matches ─────────────────────────────────────
    "painless_lumps":       ["painless_lumps"],
    "depression":           ["depression"],
    "lameness":             ["lameness", "difficulty_walking"],
    "loss_of_appetite":     ["loss_of_appetite"],

    # ── FMD — oral, tongue, pedal blisters / sores ───────────────────────
    "mouth_blisters":       ["blisters_on_mouth", "sores_on_mouth",
                             "blisters_on_gums", "sores_on_gums"],
    "tongue_sores":         ["blisters_on_tongue", "sores_on_tongue"],
    "foot_lesions":         ["blisters_on_hooves", "sores_on_hooves"],
    "drooling":             ["blisters_on_gums", "sores_on_gums"],

    # ── Respiratory / chest ───────────────────────────────────────────────
    "difficulty_breathing": ["shortness_of_breath"],
    "coughing":             ["crackling_sound"],   # CBPP: crackles on auscultation
    "rapid_shallow_breathing": ["shortness_of_breath"],
    "chest_pain_signs":     ["chest_discomfort"],

    # ── Lymphadenopathy (ECF / LSD) ───────────────────────────────────────
    "swollen_lymph_nodes":  ["swelling_in_neck"],
    "enlarged_lymph_nodes": ["swelling_in_neck", "swelling_in_extremities"],

    # ── No matching RF features — rules engine / Bayesian handles these ──
    "skin_nodules":         ["painless_lumps"],
    "fever":                [],
    "nasal_discharge":      [],
    "eye_discharge":        [],
    "diarrhoea":            [],
    "corneal_opacity":      [],
}


def _build_ml_symptoms(flutter_symptoms: dict) -> dict:
    """
    Build merged symptom dict for the ML service from Flutter's 19 symptoms.
    Includes RF feature names (24) AND original Flutter names for the rules engine.
    """
    merged: dict[str, int] = {}
    for flutter_key, raw_value in flutter_symptoms.items():
        present = _to_int(raw_value)
        for rf_feat in _FLUTTER_TO_RF.get(flutter_key, []):
            merged[rf_feat] = max(merged.get(rf_feat, 0), present)
        # Keep original Flutter name for the clinical rules engine
        merged[flutter_key] = present
    return merged


# ── ML service proxy ──────────────────────────────────────────────────────────

async def _call_ml_service(
    symptoms: dict,
    image_bytes: Optional[bytes],
    image_content_type: Optional[str],
) -> Optional[dict]:
    """
    POST to cattle_disease_ml /predict/full.
    Returns parsed JSON or None on any failure (triggers Bayesian fallback).
    """
    ml_url = (settings.ml_service_url or "").strip().rstrip("/")
    if not ml_url:
        return None

    payload_str = json.dumps({"symptoms": symptoms})

    try:
        async with httpx.AsyncClient(timeout=30.0) as client:
            if image_bytes and image_content_type:
                ext = image_content_type.split("/")[-1]
                files = {"file": (f"image.{ext}", image_bytes, image_content_type)}
                resp = await client.post(
                    f"{ml_url}/predict/full",
                    data={"payload": payload_str},
                    files=files,
                )
            else:
                resp = await client.post(
                    f"{ml_url}/predict/full",
                    data={"payload": payload_str},
                )
        resp.raise_for_status()
        return resp.json()
    except Exception as exc:
        log.warning("ML service unavailable (%s); using Bayesian fallback.", exc)
        return None


# ── ML response → Flutter format ─────────────────────────────────────────────

def _ml_to_flutter(
    ml: dict,
    temperature: Optional[float],
    severity: Optional[float],
) -> dict:
    """
    Convert cattle_disease_ml response → Flutter-compatible prediction payload.
    Enriches with display labels, recommendations, NL reasoning, and risk level.
    """
    final_label_upper = str(ml.get("final_label", "Normal"))
    disease_key = final_label_upper.lower()
    confidence = float(ml.get("confidence", 0.5))
    method = str(ml.get("method", "hybrid"))

    # Probabilities: uppercase → lowercase keys
    probs_upper: dict = ml.get("probs", {}) or {}
    probabilities = {k.lower(): round(float(v), 4) for k, v in probs_upper.items()}

    # Explainability block from ML service
    explain_raw: dict = ml.get("explain", {}) or {}
    top_symptoms_raw = explain_raw.get("top_symptoms") or []
    rule_triggers_raw = explain_raw.get("rule_triggers") or {}
    raw_feature_importance = explain_raw.get("feature_importance") or {}

    # Feature importance: from RF top_symptoms list
    # Handles formats: [["feat", score]], [("feat", score)], ["feat"], [{"feature":…}]
    feature_importance: dict[str, float] = {}
    if isinstance(raw_feature_importance, dict):
        for feat, score in raw_feature_importance.items():
            feat_name = str(feat).replace("_", " ").strip()
            if not feat_name:
                continue
            feature_importance[feat_name] = round(float(score), 4)
    if isinstance(top_symptoms_raw, list):
        for item in top_symptoms_raw:
            if isinstance(item, (list, tuple)) and len(item) >= 2:
                feat = str(item[0]).replace("_", " ")
                feature_importance[feat] = round(float(item[1]), 4)
            elif isinstance(item, str):
                feature_importance[item.replace("_", " ")] = 0.0
            elif isinstance(item, dict):
                feat = str(item.get("feature") or item.get("symptom") or item.get("name") or "").replace("_", " ")
                score = float(item.get("importance", item.get("score", 0.0)))
                if feat:
                    feature_importance[feat] = round(score, 4)

    # Normalize feature importance
    fi_total = sum(feature_importance.values())
    if fi_total > 0:
        feature_importance = {k: round(v / fi_total, 4) for k, v in feature_importance.items()}

    # Rule triggers: {"ECF": ["trig1"], "CBPP": []} → flat list of strings
    rule_triggers: list[str] = []
    if isinstance(rule_triggers_raw, dict):
        for tlist in rule_triggers_raw.values():
            if isinstance(tlist, list):
                rule_triggers.extend(str(t) for t in tlist)
    elif isinstance(rule_triggers_raw, list):
        rule_triggers = [str(t) for t in rule_triggers_raw]

    # Differential: sorted by score descending
    differential = [
        {
            "disease": k.lower(),
            "display_name": _DISPLAY_UPPER.get(k, k),
            "score": round(float(v), 4),
            "percentage": round(float(v) * 100, 1),
            "matched_symptoms": [],
        }
        for k, v in sorted(probs_upper.items(), key=lambda x: x[1], reverse=True)
    ]

    # Enrichment
    recommendations = _RECS.get(disease_key, _RECS.get("normal", []))
    risk_level = _compute_risk(disease_key, confidence, severity, temperature)
    display_label = _DISPLAY.get(disease_key, final_label_upper)
    reasoning = str(explain_raw.get("reasoning") or _build_reasoning(disease_key, confidence, top_symptoms_raw, method, temperature))
    supporting_evidence = explain_raw.get("supporting_evidence") if isinstance(explain_raw.get("supporting_evidence"), list) else []
    cautionary_evidence = explain_raw.get("cautionary_evidence") if isinstance(explain_raw.get("cautionary_evidence"), list) else []
    modality_summary = str(explain_raw.get("modality_summary") or "").strip() or None
    evidence_quality = str(explain_raw.get("evidence_quality") or "").strip() or None
    confidence_band = str(explain_raw.get("confidence_band") or "").strip() or None

    temperature_note = (
        f"Elevated temperature ({temperature:.1f}°C) supports fever-based diseases"
        if temperature and temperature > 39.5 else None
    )
    severity_note = (
        f"High severity ({severity:.0%}) indicates advanced presentation"
        if severity and severity > 0.7 else None
    )

    return {
        "display_label":   display_label,
        "final_label":     disease_key,
        "prediction":      display_label,
        "confidence":      round(confidence, 4),
        "method":          method,
        "risk_level":      risk_level,
        "recommendations": recommendations,
        "explain": {
            "gradcam_path":          explain_raw.get("gradcam_path"),
            "feature_importance":    feature_importance,
            "differential":          differential,
            "rule_triggers":         rule_triggers,
            "reasoning":             reasoning,
            "probabilities":         probabilities,
            "temperature_note":      temperature_note,
            "severity_note":         severity_note,
            # ML transparency fields
            "symptom_reliability":   float(explain_raw.get("symptom_reliability", 0.0)),
            "symptom_advisory_only": bool(explain_raw.get("symptom_advisory_only", False)),
            "symptom_training_mode": str(explain_raw.get("symptom_model_training_mode", "unknown")),
            "symptom_warning":       str(explain_raw.get("symptom_model_warning", "")),
            "catalog_match_scores":  explain_raw.get("catalog_match_scores", {}),
            "clinical_advisories":   explain_raw.get("clinical_advisories", {}),
            "supporting_evidence":   [str(x) for x in supporting_evidence],
            "cautionary_evidence":   [str(x) for x in cautionary_evidence],
            "modality_summary":      modality_summary,
            "evidence_quality":      evidence_quality,
            "confidence_band":       confidence_band,
            "modality_contributions": explain_raw.get("modality_contributions", {}),
            "modality_outputs":      explain_raw.get("modality_outputs", {}),
            "rule_score_breakdown":  explain_raw.get("rule_score_breakdown", {}),
            "predicted_disease_catalog_evidence": explain_raw.get("predicted_disease_catalog_evidence", {}),
            "input_summary":         explain_raw.get("input_summary", {}),
            "probability_ranked":    explain_raw.get("probability_ranked", []),
            "differential_summary":  explain_raw.get("differential_summary", {}),
            "explanation_version":   explain_raw.get("explanation_version"),
        },
        # Top-level copies for clients that read them directly
        "gradcam_path":       explain_raw.get("gradcam_path"),
        "rule_triggers":      rule_triggers,
        "rule_triggers_by_disease": explain_raw.get("rule_triggers", {}) if isinstance(explain_raw.get("rule_triggers"), dict) else None,
        "feature_importance": feature_importance,
        "differential":       differential,
        "reasoning":          reasoning,
        "probabilities":      probabilities,
        "supporting_evidence": [str(x) for x in supporting_evidence],
        "cautionary_evidence": [str(x) for x in cautionary_evidence],
        "modality_summary":   modality_summary,
        "evidence_quality":   evidence_quality,
        "confidence_band":    confidence_band,
        "retake_image": bool(
            (ml.get("recommendation_flags") or {}).get("retake_image", False)
        ),
        "contact_vet_urgent": bool(
            (ml.get("recommendation_flags") or {}).get("contact_vet_urgent", False)
        ),
    }


# ── Main endpoint ─────────────────────────────────────────────────────────────

def _extract_gradcam_path(prediction: dict) -> Optional[str]:
    explain = prediction.get("explain")
    candidate = None
    if isinstance(explain, dict):
        candidate = explain.get("gradcam_path")
    if not candidate:
        candidate = prediction.get("gradcam_path")
    text = str(candidate or "").strip()
    return text or None


def _set_gradcam_path(prediction: dict, gradcam_url: str) -> None:
    prediction["gradcam_path"] = gradcam_url
    explain = prediction.get("explain")
    if isinstance(explain, dict):
        explain["gradcam_path"] = gradcam_url


async def _ensure_gradcam_public_url(prediction: dict) -> None:
    """Convert an ML-local Grad-CAM path to a client-accessible public URL."""
    gradcam_path = _extract_gradcam_path(prediction)
    if not gradcam_path:
        return
    if gradcam_path.startswith("http://") or gradcam_path.startswith("https://"):
        return

    filename = os.path.basename(gradcam_path.replace("\\", "/")).strip()
    if not filename or "/" in filename or "\\" in filename or ".." in filename:
        return

    ml_url = os.getenv("ML_SERVICE_URL", settings.ml_service_url or "http://ml:8000").rstrip("/")
    if not ml_url:
        return
    artifact_url = f"{ml_url}/artifacts/gradcam/{quote(filename)}"

    try:
        async with httpx.AsyncClient(timeout=20.0) as client:
            response = await client.get(artifact_url)
            response.raise_for_status()
        content_type = (response.headers.get("content-type") or "image/png").split(";")[0].strip().lower()
        if not content_type.startswith("image/"):
            content_type = "image/png"

        from app.core.supabase_client import upload_image

        object_name = f"gradcam/{uuid.uuid4().hex}_{filename}"
        public_url = upload_image(object_name, response.content, content_type)
        _set_gradcam_path(prediction, public_url)
    except Exception as exc:
        log.warning("Unable to materialize Grad-CAM '%s': %s", gradcam_path, exc)


@router.post("/predict/full")
async def predict_full(
    payload: str = Form(..., description="JSON: {symptoms:{…}, temperature:?, severity:?}"),
    file: UploadFile | None = File(default=None, description="Optional case image"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
) -> dict:
    """
    Run disease prediction and return full explainability output.

    Routes to cattle_disease_ml service (CNN + RF + clinical rules) when available.
    Falls back to local Bayesian engine automatically on any ML service failure.

    Payload JSON schema:
        {
            "symptoms":    { "fever": 1, "skin_nodules": 1, ... },
            "temperature": 40.2,   // optional, °C
            "severity":    0.75,   // optional, 0–1
            "animal_id":   "..."   // optional
        }
    """
    # ── Parse payload ─────────────────────────────────────────────────────
    try:
        data = json.loads(payload)
    except (json.JSONDecodeError, ValueError):
        raise HTTPException(status_code=422, detail="payload must be valid JSON")

    raw_symptoms: dict = data.get("symptoms") or {}
    if not isinstance(raw_symptoms, dict) or not raw_symptoms:
        raise HTTPException(
            status_code=422,
            detail="At least one symptom must be provided in 'symptoms' object",
        )

    temperature: float | None = _parse_float(data.get("temperature"))
    severity: float | None = _parse_float(data.get("severity"))

    # ── Save uploaded image ───────────────────────────────────────────────
    image_url: str | None = None
    image_bytes: bytes | None = None
    image_content_type: str | None = None

    if file and file.filename:
        content_type = file.content_type or ""
        if content_type not in _ALLOWED_IMAGE_TYPES:
            raise HTTPException(
                status_code=415,
                detail=f"Unsupported image type '{content_type}'. Allowed: jpeg, png, webp",
            )
        image_bytes = await file.read()
        if len(image_bytes) > _MAX_IMAGE_BYTES:
            raise HTTPException(status_code=413, detail="Image exceeds 10 MB limit")

        image_content_type = content_type
        ext = _extension_from_content_type(content_type)
        filename = f"{uuid.uuid4().hex}{ext}"
        from app.core.supabase_client import upload_image
        image_url = upload_image(filename, image_bytes, content_type)

    # ── Primary: cattle_disease_ml microservice ───────────────────────────
    ml_symptoms = _build_ml_symptoms(raw_symptoms)
    ml_result = await _call_ml_service(ml_symptoms, image_bytes, image_content_type)

    if ml_result is not None:
        response = _ml_to_flutter(ml_result, temperature, severity)
        await _ensure_gradcam_public_url(response)
        response["image_url"] = image_url
        response["predicted_at"] = datetime.utcnow().isoformat()
        response["engine"] = "ml_service"
        return response

    # ── Fallback: local Bayesian engine ───────────────────────────────────
    log.info("Bayesian fallback engaged for predict/full")
    bool_symptoms = {k: bool(_to_int(v)) for k, v in raw_symptoms.items()}

    prediction_result = bayesian_predict(
        symptoms=bool_symptoms,
        temperature=temperature,
        severity=severity,
    )
    explanation = bayesian_explain(
        prediction_result=prediction_result,
        temperature=temperature,
        severity=severity,
    )

    top_disease = explanation["label"]
    confidence = explanation["confidence"]

    response = {
        "display_label":   explanation["display_label"],
        "final_label":     top_disease,
        "label":           top_disease,
        "prediction":      top_disease,
        "confidence":      confidence,
        "method":          explanation["method"],
        "risk_level":      explanation["risk_level"],
        "recommendations": explanation["recommendations"],
        "explain": {
            "gradcam_path":       None,
            "feature_importance": explanation["feature_importance"],
            "differential":       explanation["differential"],
            "rule_triggers":      explanation["rule_triggers"],
            "reasoning":          explanation["reasoning"],
            "probabilities":      explanation["probabilities"],
            "temperature_note":   explanation.get("temperature_note"),
            "severity_note":      explanation.get("severity_note"),
        },
        "gradcam_path":       None,
        "rule_triggers":      explanation["rule_triggers"],
        "feature_importance": explanation["feature_importance"],
        "differential":       explanation["differential"],
        "reasoning":          explanation["reasoning"],
        "probabilities":      explanation["probabilities"],
        "image_url":          image_url,
        "predicted_at":       datetime.utcnow().isoformat(),
        "engine":             "bayesian_fallback",
    }
    return response


# ── Utilities ─────────────────────────────────────────────────────────────────

def _to_int(value) -> int:
    if isinstance(value, bool):
        return int(value)
    try:
        return int(float(value) > 0)
    except (TypeError, ValueError):
        return 0


def _parse_float(value) -> Optional[float]:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _extension_from_content_type(content_type: str) -> str:
    return {
        "image/jpeg": ".jpg", "image/png": ".png",
        "image/webp": ".webp", "image/gif": ".gif",
    }.get(content_type, ".jpg")


def _compute_risk(
    disease_key: str,
    confidence: float,
    severity: Optional[float],
    temperature: Optional[float],
) -> str:
    if disease_key == "normal":
        return "low"
    base_high = {"lsd": 0.70, "fmd": 0.65, "ecf": 0.60, "cbpp": 0.65}
    threshold = base_high.get(disease_key, 0.70)
    if severity and severity > 0.8:
        threshold -= 0.10
    if temperature and temperature > 40.5:
        threshold -= 0.05
    if confidence >= threshold:
        return "high"
    if confidence >= threshold - 0.20:
        return "medium"
    return "low"


def _build_reasoning(
    disease_key: str,
    confidence: float,
    top_symptoms_raw,
    method: str,
    temperature: Optional[float],
) -> str:
    display = _DISPLAY.get(disease_key, disease_key.upper())
    pct = round(confidence * 100, 1)

    readable: list[str] = []
    if isinstance(top_symptoms_raw, list):
        for item in top_symptoms_raw[:3]:
            if isinstance(item, (list, tuple)) and item:
                readable.append(str(item[0]).replace("_", " "))
            elif isinstance(item, str):
                readable.append(item.replace("_", " "))
            elif isinstance(item, dict):
                feat = item.get("display_name") or item.get("feature") or item.get("symptom") or item.get("name")
                if feat:
                    readable.append(str(feat).replace("_", " "))
    top_str = ", ".join(readable) if readable else "multiple clinical indicators"

    method_map = {
        "image_model":      "image analysis (CNN)",
        "hybrid":           "hybrid image + symptom analysis",
        "clinical_rules":   "clinical rule assessment",
        "symptom_model":    "symptom analysis (Random Forest)",
        "symptom_bayesian": "Bayesian symptom analysis",
    }
    method_str = method_map.get(method, method)
    temp_str = (
        f" Elevated temperature ({temperature:.1f}°C) is consistent with systemic infection."
        if temperature and temperature > 39.5 else ""
    )

    return (
        f"{pct}% confidence for {display} via {method_str}. "
        f"Key indicators: {top_str}.{temp_str} "
        f"Consult a veterinarian for clinical confirmation."
    )

from __future__ import annotations

import json
import mimetypes
import os
import uuid
import urllib.error
import urllib.parse
import urllib.request
from typing import Any

from fastapi import HTTPException

from .settings import (
    INFERENCE_ALLOW_RULES_FALLBACK,
    INFERENCE_API_URL,
    INFERENCE_STRICT_MODE,
    INFERENCE_TIMEOUT_SECONDS,
)


def _safe_float(value: Any) -> float | None:
    if value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    try:
        return float(str(value))
    except Exception:
        return None


def _flatten_rule_triggers(raw: Any) -> list[str]:
    if isinstance(raw, list):
        return [str(item) for item in raw]
    if isinstance(raw, dict):
        out: list[str] = []
        for value in raw.values():
            if isinstance(value, list):
                out.extend(str(item) for item in value)
        return out
    return []


def _extract_feature_importance(decoded: dict[str, Any], explain: dict[str, Any]) -> dict[str, float]:
    raw = explain.get("feature_importance")
    if isinstance(raw, dict):
        out: dict[str, float] = {}
        for k, v in raw.items():
            score = _safe_float(v)
            if score is not None:
                out[str(k)] = round(score, 4)
        return out

    top = explain.get("top_symptoms")
    out: dict[str, float] = {}
    if isinstance(top, list):
        for item in top:
            if isinstance(item, dict):
                feat = str(item.get("feature") or item.get("symptom") or item.get("name") or "").strip()
                score = _safe_float(item.get("importance") or item.get("score"))
            elif isinstance(item, (list, tuple)) and item:
                feat = str(item[0]).strip()
                score = _safe_float(item[1]) if len(item) > 1 else 0.0
            elif isinstance(item, str):
                feat = item.strip()
                score = 0.0
            else:
                feat = ""
                score = None
            if feat:
                out[feat] = round(float(score or 0.0), 4)
    if out:
        total = sum(out.values())
        if total > 0:
            out = {k: round(v / total, 4) for k, v in out.items()}
    return out


def _extract_probabilities(decoded: dict[str, Any], explain: dict[str, Any]) -> dict[str, float]:
    raw = decoded.get("probs") or explain.get("probabilities") or decoded.get("probabilities") or {}
    if not isinstance(raw, dict):
        return {}
    out: dict[str, float] = {}
    for k, v in raw.items():
        score = _safe_float(v)
        if score is None:
            continue
        out[str(k).lower()] = round(score, 4)
    return out

def _predict(symptoms: dict[str, bool], temperature: float | None) -> dict[str, Any]:
    fever = symptoms.get("fever", False) or ((temperature or 0) >= 39.0)
    nodules = symptoms.get("skin_nodules", False)
    mouth_lesions = symptoms.get("mouth_lesions", False)
    breathing = symptoms.get("difficulty_breathing", False)
    lameness = symptoms.get("lameness", False)
    nasal = symptoms.get("nasal_discharge", False)

    if nodules and fever:
        disease = "LSD"
    elif mouth_lesions and lameness:
        disease = "FMD"
    elif fever and breathing:
        disease = "CBPP"
    elif fever and nasal:
        disease = "ECF"
    elif not any(symptoms.values()) and not fever:
        disease = "Normal"
    else:
        disease = "Unknown"

    symptom_count = sum(1 for value in symptoms.values() if value)
    base = 0.75 if disease == "Normal" else 0.7
    confidence = min(0.97, base + symptom_count * 0.04)

    rec_map = {
        "LSD": [
            "Isolate affected cattle from the herd immediately.",
            "Disinfect shared feed and water points.",
            "Consult a veterinarian for confirmatory diagnosis.",
        ],
        "FMD": [
            "Restrict animal movement and herd contact.",
            "Disinfect housing and feeding zones daily.",
            "Call veterinary services to manage spread.",
        ],
        "ECF": [
            "Improve tick control around barns and fields.",
            "Monitor body temperature twice daily.",
            "Consult a veterinarian for targeted treatment.",
        ],
        "CBPP": [
            "Separate suspected animals and improve ventilation.",
            "Avoid transport until veterinary review.",
            "Seek urgent diagnosis and treatment guidance.",
        ],
    }
    recommendations = rec_map.get(
        disease,
        [
            "Continue routine observation and preventive care.",
            "Retake photos if symptoms change.",
            "Maintain vaccination and treatment records.",
        ],
    )

    active_symptoms = [k for k, v in symptoms.items() if v]
    if fever and "fever" not in active_symptoms:
        active_symptoms.append("fever")
    active_symptoms = sorted(set(active_symptoms))

    if disease == "LSD":
        rule_triggers = ["fever_with_skin_nodules"] if fever and nodules else ["skin_nodule_pattern"]
    elif disease == "FMD":
        rule_triggers = ["mouth_lesions_with_lameness"] if mouth_lesions and lameness else ["vesicular_or_pedal_pattern"]
    elif disease == "CBPP":
        rule_triggers = ["fever_with_respiratory_distress"]
    elif disease == "ECF":
        rule_triggers = ["fever_with_nasal_discharge"]
    elif disease == "Normal":
        rule_triggers = ["no_significant_symptoms_reported"]
    else:
        rule_triggers = ["mixed_non_specific_symptom_pattern"]

    if disease == "Unknown":
        unknown_score = round(min(0.6, max(0.25, confidence)), 4)
        probabilities = {
            "unknown": unknown_score,
            "lsd": 0.0,
            "fmd": 0.0,
            "ecf": 0.0,
            "cbpp": 0.0,
            "normal": 0.0,
        }
        other_keys = [k for k in probabilities if k != "unknown"]
        if other_keys:
            share = round(max(0.0, 1.0 - unknown_score) / len(other_keys), 4)
            for key in other_keys:
                probabilities[key] = share
    else:
        probabilities = {
            "normal": 0.0,
            "lsd": 0.0,
            "fmd": 0.0,
            "ecf": 0.0,
            "cbpp": 0.0,
        }
        probabilities[disease.lower()] = round(confidence, 4)
        remainder = max(0.0, 1.0 - float(probabilities[disease.lower()]))
        others = [k for k in probabilities if k != disease.lower()]
        if others:
            share = round(remainder / len(others), 4)
            for key in others:
                probabilities[key] = share

    feature_importance = {}
    if active_symptoms:
        per = round(1.0 / len(active_symptoms), 4)
        feature_importance = {sym: per for sym in active_symptoms}

    reasoning = (
        f"{disease} predicted at {confidence * 100:.1f}% confidence using the backend rules fallback. "
        + (
            f"Active indicators: {', '.join(sym.replace('_', ' ') for sym in active_symptoms[:5])}. "
            if active_symptoms
            else "No strong symptom indicators were reported. "
        )
        + "Use this as preliminary screening and confirm clinically."
    )

    return {
        "prediction": disease,
        "confidence": confidence,
        "method": "Backend Rules Engine",
        "gradcamPath": None,
        "recommendations": recommendations,
        "probabilities": probabilities,
        "feature_importance": feature_importance,
        "rule_triggers": rule_triggers,
        "reasoning": reasoning,
        "evidence_quality": "limited" if disease == "Unknown" else "moderate",
        "confidence_band": "high" if confidence >= 0.85 else "moderate" if confidence >= 0.60 else "low",
        "supporting_evidence": [f"Active symptoms: {', '.join(active_symptoms)}"] if active_symptoms else [],
        "cautionary_evidence": [
            "External ML service unavailable; Grad-CAM and multimodal fusion explainability are not available."
        ],
    }


def _predict_with_external_service(
    *,
    symptoms: dict[str, bool],
    temperature: float | None,
    image_path: str | None,
    animal_id: str | None,
) -> dict[str, Any]:
    if not INFERENCE_API_URL:
        if INFERENCE_ALLOW_RULES_FALLBACK:
            fallback = _predict(symptoms, temperature)
            fallback["method"] = "Backend Rules Engine (no external model URL)"
            return fallback
        raise HTTPException(
            status_code=503,
            detail="External model URL is not configured. Set INFERENCE_API_URL.",
        )

    try:
        decoded = _call_external_inference(
            symptoms=symptoms,
            temperature=temperature,
            image_path=image_path,
            animal_id=animal_id,
        )
        prediction = (
            decoded.get("prediction")
            or decoded.get("disease")
            or decoded.get("label")
            or decoded.get("final_label")
            or decoded.get("display_label")
            or "Unknown"
        )
        normalized_prediction = _normalize_model_prediction(str(prediction))
        if normalized_prediction is None:
            raise ValueError("Unsupported model class. Expected Normal/LSD/FMD/ECF/CBPP.")

        confidence_raw = (
            decoded.get("confidence")
            or decoded.get("probability")
            or decoded.get("score")
            or decoded.get("conf")
        )
        confidence = _safe_float(confidence_raw)

        recommendations = decoded.get("recommendations") or decoded.get("next_steps") or []
        if not isinstance(recommendations, list):
            recommendations = []
        recommendations = [str(item) for item in recommendations]
        if not recommendations:
            recommendations = _default_recommendations_for_class(normalized_prediction)

        explain = decoded.get("explain") if isinstance(decoded.get("explain"), dict) else {}
        rule_triggers = _flatten_rule_triggers(explain.get("rule_triggers") or decoded.get("rule_triggers"))
        feature_importance = _extract_feature_importance(decoded, explain)
        probabilities = _extract_probabilities(decoded, explain)
        reasoning = (
            explain.get("reasoning")
            or decoded.get("reasoning")
            or decoded.get("summary")
            or None
        )
        temperature_note = explain.get("temperature_note") or decoded.get("temperature_note")
        severity_note = explain.get("severity_note") or decoded.get("severity_note")
        supporting_evidence = explain.get("supporting_evidence") if isinstance(explain.get("supporting_evidence"), list) else []
        cautionary_evidence = explain.get("cautionary_evidence") if isinstance(explain.get("cautionary_evidence"), list) else []
        evidence_quality = explain.get("evidence_quality") or decoded.get("evidence_quality")
        confidence_band = explain.get("confidence_band") or decoded.get("confidence_band")
        modality_summary = explain.get("modality_summary") or decoded.get("modality_summary")
        gradcam_path = (
            decoded.get("gradcamPath")
            or decoded.get("gradcam_path")
            or decoded.get("gradcam")
            or decoded.get("cam")
            or explain.get("gradcam_path")
        )

        return {
            "prediction": normalized_prediction,
            "confidence": confidence,
            "method": str(decoded.get("method") or "External Inference API"),
            "modelVersion": decoded.get("modelVersion") or decoded.get("model_version"),
            "gradcamPath": gradcam_path,
            "recommendations": recommendations,
            # Explainability payload (kept top-level for stored case JSON + under raw for future compatibility)
            "probabilities": probabilities,
            "feature_importance": feature_importance,
            "rule_triggers": rule_triggers,
            "rule_triggers_by_disease": explain.get("rule_triggers") if isinstance(explain.get("rule_triggers"), dict) else None,
            "reasoning": None if reasoning is None else str(reasoning),
            "temperature_note": None if temperature_note is None else str(temperature_note),
            "severity_note": None if severity_note is None else str(severity_note),
            "supporting_evidence": [str(x) for x in supporting_evidence],
            "cautionary_evidence": [str(x) for x in cautionary_evidence],
            "evidence_quality": None if evidence_quality is None else str(evidence_quality),
            "confidence_band": None if confidence_band is None else str(confidence_band),
            "modality_summary": None if modality_summary is None else str(modality_summary),
            "modality_contributions": explain.get("modality_contributions", {}),
            "modality_outputs": explain.get("modality_outputs", {}),
            "input_summary": explain.get("input_summary", {}),
            "probability_ranked": explain.get("probability_ranked", []),
            "raw": decoded,
        }
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError, ValueError, json.JSONDecodeError):
        if INFERENCE_STRICT_MODE or not INFERENCE_ALLOW_RULES_FALLBACK:
            raise HTTPException(
                status_code=502,
                detail="External inference service unavailable or returned invalid output.",
            )
        fallback = _predict(symptoms, temperature)
        fallback["method"] = "Backend Rules Engine (fallback)"
        return fallback


def _call_external_inference(
    *,
    symptoms: dict[str, bool],
    temperature: float | None,
    image_path: str | None,
    animal_id: str | None,
) -> dict[str, Any]:
    # Try JSON first for APIs that accept structured payloads.
    json_payload = {
        "symptoms": symptoms,
        "temperature": temperature,
        "imagePath": image_path,
        "animalId": animal_id,
    }
    json_request = urllib.request.Request(
        INFERENCE_API_URL,
        data=json.dumps(json_payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(json_request, timeout=INFERENCE_TIMEOUT_SECONDS) as response:
            body = response.read().decode("utf-8")
            decoded = json.loads(body) if body else {}
            if isinstance(decoded, dict):
                return decoded
    except Exception:
        # Fall through to multipart / form payload styles.
        pass

    # Try multipart payload style for FastAPI endpoints that expect:
    #   POST /predict/full
    #   form field: payload='{"symptoms": {...}}'
    multipart_payload: dict[str, Any] = {"symptoms": symptoms}
    if temperature is not None:
        multipart_payload["temperature"] = temperature
    if animal_id:
        multipart_payload["animal_id"] = animal_id
    body_bytes, content_type = _encode_multipart_form_data(
        fields={"payload": json.dumps(multipart_payload)},
        file_field="file",
        image_path=image_path,
    )
    multipart_request = urllib.request.Request(
        INFERENCE_API_URL,
        data=body_bytes,
        headers={"Content-Type": content_type},
        method="POST",
    )
    try:
        with urllib.request.urlopen(multipart_request, timeout=INFERENCE_TIMEOUT_SECONDS) as response:
            body = response.read().decode("utf-8")
            decoded = json.loads(body) if body else {}
            if isinstance(decoded, dict):
                return decoded
    except Exception:
        # Fall through to x-www-form-urlencoded style.
        pass

    form_payload: dict[str, str] = {}
    for key, value in symptoms.items():
        form_payload[key] = "1" if value else "0"
    if temperature is not None:
        form_payload["temperature"] = str(temperature)
    if animal_id:
        form_payload["animal_id"] = animal_id
    form_payload["imagePath"] = image_path or ""

    form_request = urllib.request.Request(
        INFERENCE_API_URL,
        data=urllib.parse.urlencode(form_payload).encode("utf-8"),
        headers={"Content-Type": "application/x-www-form-urlencoded"},
        method="POST",
    )
    with urllib.request.urlopen(form_request, timeout=INFERENCE_TIMEOUT_SECONDS) as response:
        body = response.read().decode("utf-8")
        decoded = json.loads(body) if body else {}
        if not isinstance(decoded, dict):
            raise ValueError("Invalid inference payload shape.")
        return decoded


def _encode_multipart_form_data(
    *,
    fields: dict[str, str],
    file_field: str,
    image_path: str | None,
) -> tuple[bytes, str]:
    boundary = f"----sudvet-{uuid.uuid4().hex}"
    chunks: list[bytes] = []

    for key, value in fields.items():
        chunks.extend(
            [
                f"--{boundary}\r\n".encode("utf-8"),
                f'Content-Disposition: form-data; name="{key}"\r\n\r\n'.encode("utf-8"),
                str(value).encode("utf-8"),
                b"\r\n",
            ]
        )

    if image_path:
        normalized_path = os.path.expanduser(str(image_path).strip())
        if normalized_path and os.path.isfile(normalized_path):
            with open(normalized_path, "rb") as f:
                file_bytes = f.read()
            file_name = os.path.basename(normalized_path) or "upload.jpg"
            mime_type = mimetypes.guess_type(file_name)[0] or "application/octet-stream"
            chunks.extend(
                [
                    f"--{boundary}\r\n".encode("utf-8"),
                    (
                        f'Content-Disposition: form-data; name="{file_field}"; filename="{file_name}"\r\n'
                    ).encode("utf-8"),
                    f"Content-Type: {mime_type}\r\n\r\n".encode("utf-8"),
                    file_bytes,
                    b"\r\n",
                ]
            )

    chunks.append(f"--{boundary}--\r\n".encode("utf-8"))
    content_type = f"multipart/form-data; boundary={boundary}"
    return b"".join(chunks), content_type


def _normalize_model_prediction(raw: str) -> str | None:
    value = raw.strip().lower()
    if not value:
        return None
    if value in {"normal", "healthy"}:
        return "Normal"
    if "lsd" in value or "lumpy" in value:
        return "LSD"
    if "fmd" in value or "foot" in value or "mouth" in value:
        return "FMD"
    if "ecf" in value or "east coast fever" in value:
        return "ECF"
    if "cbpp" in value or "pleuropneumonia" in value:
        return "CBPP"
    return None


def _default_recommendations_for_class(prediction: str) -> list[str]:
    if prediction == "LSD":
        return [
            "Isolate affected cattle from the herd immediately.",
            "Disinfect shared feed and water points.",
            "Consult a veterinarian for confirmatory diagnosis.",
        ]
    if prediction == "FMD":
        return [
            "Restrict animal movement and herd contact.",
            "Disinfect housing and feeding zones daily.",
            "Call veterinary services to manage spread.",
        ]
    if prediction == "ECF":
        return [
            "Improve tick control around barns and grazing areas.",
            "Monitor temperature and appetite closely over the next 24 hours.",
            "Consult a veterinarian for targeted treatment guidance.",
        ]
    if prediction == "CBPP":
        return [
            "Isolate suspected animals and reduce herd movement.",
            "Improve ventilation and monitor respiratory distress signs.",
            "Seek urgent veterinary assessment and confirmatory diagnosis.",
        ]
    return [
        "Continue routine observation and preventive care.",
        "Retake photos if symptoms change.",
        "Maintain vaccination and treatment records.",
    ]

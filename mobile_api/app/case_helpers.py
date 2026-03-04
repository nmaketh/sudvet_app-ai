from __future__ import annotations

import json
import sqlite3
from typing import Any

from .security import now_iso

def _disease_from_prediction(prediction_json: dict[str, Any] | None) -> str:
    if not prediction_json:
        return "unknown"
    prediction = str(prediction_json.get("prediction", "")).strip().lower()
    if "normal" in prediction:
        return "normal"
    if "lsd" in prediction:
        return "lsd"
    if "fmd" in prediction:
        return "fmd"
    if "ecf" in prediction:
        return "ecf"
    if "cbpp" in prediction:
        return "cbpp"
    return "unknown"

def _case_from_row(row: sqlite3.Row) -> dict[str, Any]:
    symptoms_json = row["symptomsJson"] or "{}"
    prediction_json_raw = row["predictionJson"]
    attachments_json = row["attachmentsJson"] or "[]"
    return {
        "id": row["id"],
        "animalId": row["animalId"],
        "animalName": row["animalName"],
        "animalTag": row["animalTag"],
        "createdAt": row["createdAt"],
        "imagePath": row["imagePath"],
        "symptomsJson": json.loads(symptoms_json),
        "status": row["status"],
        "predictionJson": json.loads(prediction_json_raw) if prediction_json_raw else None,
        "followUpStatus": row["followUpStatus"],
        "followUpDate": row["followUpDate"],
        "notes": row["notes"],
        "syncedAt": row["syncedAt"],
        "temperature": row["temperature"],
        "severity": row["severity"],
        "attachmentsJson": json.loads(attachments_json),
    }


def _case_export_payload(row: sqlite3.Row) -> dict[str, Any]:
    case_data = _case_from_row(row)
    prediction_json = case_data.get("predictionJson") or {}
    symptoms = case_data.get("symptomsJson") or {}
    active_symptoms = [key for key, value in symptoms.items() if value]

    summary_lines = [
        f"Case ID: {case_data['id']}",
        f"Animal: {case_data.get('animalName') or 'Quick Case'} ({case_data.get('animalTag') or '-'})",
        f"Created At: {case_data.get('createdAt')}",
        f"Status: {case_data.get('status')}",
        f"Prediction: {prediction_json.get('prediction', 'Pending')}",
        f"Confidence: {prediction_json.get('confidence', 'N/A')}",
        f"Method: {prediction_json.get('method', 'N/A')}",
        f"Temperature: {case_data.get('temperature') if case_data.get('temperature') is not None else 'N/A'}",
        f"Severity: {case_data.get('severity') if case_data.get('severity') is not None else 'N/A'}",
        f"Symptoms: {', '.join(active_symptoms) if active_symptoms else 'None flagged'}",
    ]
    notes = case_data.get("notes")
    if notes:
        summary_lines.append(f"Notes: {notes}")

    recommendations = prediction_json.get("recommendations") or []
    if isinstance(recommendations, list) and recommendations:
        summary_lines.append("Recommendations:")
        for item in recommendations:
            summary_lines.append(f"- {item}")

    return {
        "caseId": case_data["id"],
        "generatedAt": now_iso(),
        "summaryText": "\n".join(summary_lines),
        "data": case_data,
    }


def _gradcam_svg_for_case(row: sqlite3.Row) -> str:
    symptoms = json.loads(row["symptomsJson"] or "{}")
    score = sum(1 for value in symptoms.values() if value)
    intensity = min(1.0, 0.25 + (score * 0.12))
    alpha = max(0.20, min(0.85, intensity))

    return f"""<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 600 320">
  <defs>
    <radialGradient id="hotspot" cx="50%" cy="50%" r="50%">
      <stop offset="0%" stop-color="rgba(255,0,0,{alpha:.2f})" />
      <stop offset="60%" stop-color="rgba(255,153,0,{alpha * 0.8:.2f})" />
      <stop offset="100%" stop-color="rgba(0,0,0,0.0)" />
    </radialGradient>
    <linearGradient id="bg" x1="0%" y1="0%" x2="100%" y2="100%">
      <stop offset="0%" stop-color="#e8f2ec" />
      <stop offset="100%" stop-color="#d8e6df" />
    </linearGradient>
  </defs>
  <rect x="0" y="0" width="600" height="320" rx="16" fill="url(#bg)" />
  <ellipse cx="200" cy="145" rx="145" ry="92" fill="url(#hotspot)" />
  <ellipse cx="360" cy="162" rx="125" ry="88" fill="url(#hotspot)" />
  <ellipse cx="285" cy="220" rx="110" ry="64" fill="url(#hotspot)" />
  <text x="20" y="298" font-size="18" font-family="Arial, sans-serif" fill="#1f3d2f">
    Explainability Map (synthetic Grad-CAM)
  </text>
</svg>"""

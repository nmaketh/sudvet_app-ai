"""
Explainability layer: converts raw predictor output into human-readable
diagnostics — natural language reasoning, rule triggers, risk level,
structured recommendations, and temperature/severity annotations.
"""

from .disease_rules import (
    DISEASE_DISPLAY,
    DISEASE_RECOMMENDATIONS,
    DISEASE_SHORT,
)


# ── Risk thresholds per disease ───────────────────────────────────────────────

_RISK_HIGH_THRESHOLD: dict[str, float] = {
    "lsd":    0.68,
    "fmd":    0.62,
    "ecf":    0.58,
    "cbpp":   0.62,
    "normal": 1.01,  # normal is never high risk
}


def explain(
    prediction_result: dict,
    temperature: float | None,
    severity: float | None,
) -> dict:
    """
    Build the full explainability payload from a predictor output dict.

    Returns a dict ready to be stored in ``prediction_json`` on the Case model
    and served directly to the Flutter app / dashboard.
    """
    top = prediction_result["top_disease"]
    confidence = prediction_result["confidence"]
    differential = prediction_result["differential"]
    feature_importance = prediction_result["feature_importance"]
    active_symptoms: list[str] = prediction_result["active_symptoms"]
    probabilities: dict[str, float] = prediction_result["probabilities"]

    rule_triggers = _compute_rule_triggers(top, active_symptoms)
    risk_level = _compute_risk(top, confidence, severity, temperature)
    reasoning = _build_reasoning(
        top, confidence, feature_importance, differential, temperature, severity
    )
    temp_note = (
        f"Elevated temperature ({temperature:.1f} °C) supports fever-based diseases"
        if temperature and temperature > 39.5
        else None
    )
    sev_note = (
        f"High severity ({severity:.0%}) indicates an advanced or acute presentation"
        if severity and severity > 0.70
        else None
    )

    return {
        # ── Core prediction fields (Flutter api_client.dart lookups) ───────
        "label":         top,
        "display_label": DISEASE_DISPLAY[top],
        "confidence":    confidence,
        "method":        "symptom_bayesian",
        "risk_level":    risk_level,

        # ── Explainability ────────────────────────────────────────────────
        "differential":       differential,
        "feature_importance": feature_importance,
        "rule_triggers":      rule_triggers,
        "reasoning":          reasoning,
        "probabilities":      probabilities,

        # ── Recommendations ───────────────────────────────────────────────
        "recommendations": DISEASE_RECOMMENDATIONS[top],

        # ── Contextual notes ──────────────────────────────────────────────
        "temperature_note": temp_note,
        "severity_note":    sev_note,

        # ── Placeholder for future image explainability ───────────────────
        "gradcam_url": None,
    }


# ── Internal helpers ──────────────────────────────────────────────────────────

def _compute_rule_triggers(disease: str, active_symptoms: list[str]) -> list[str]:
    rules: list[str] = []
    s = set(active_symptoms)

    if disease == "lsd":
        if "skin_nodules" in s and "painless_lumps" in s:
            rules.append("pathognomonic_lsd_nodule_pattern")
        if "fever" in s and "skin_nodules" in s:
            rules.append("fever_with_dermal_lesions")
        if "enlarged_lymph_nodes" in s:
            rules.append("lymphadenopathy_present")
        if "temperature_elevated" in s:
            rules.append("elevated_temperature_supports_lsd")

    elif disease == "fmd":
        if "mouth_blisters" in s and "foot_lesions" in s:
            rules.append("classic_fmd_vesicular_pattern")
        if "drooling" in s and "tongue_sores" in s:
            rules.append("oral_vesicular_lesions")
        if "lameness" in s and "foot_lesions" in s:
            rules.append("pedal_vesicular_lesions")
        if "fever" in s and "mouth_blisters" in s:
            rules.append("febrile_oral_vesiculation")

    elif disease == "ecf":
        if "fever" in s and "swollen_lymph_nodes" in s:
            rules.append("ecf_fever_lymphadenopathy_pattern")
        if "corneal_opacity" in s:
            rules.append("corneal_opacity_ecf_indicator")
        if "temperature_elevated" in s and "depression" in s:
            rules.append("high_fever_with_depression_ecf")

    elif disease == "cbpp":
        if "difficulty_breathing" in s and "coughing" in s:
            rules.append("respiratory_distress_pattern")
        if "chest_pain_signs" in s:
            rules.append("pleuropneumonia_chest_signs")
        if "nasal_discharge" in s and "coughing" in s:
            rules.append("productive_respiratory_signs")

    elif disease == "normal":
        if not s or s == {"temperature_elevated"}:
            rules.append("no_significant_clinical_signs")

    return rules


def _compute_risk(
    disease: str,
    confidence: float,
    severity: float | None,
    temperature: float | None,
) -> str:
    if disease == "normal":
        return "low"

    threshold = _RISK_HIGH_THRESHOLD.get(disease, 0.68)

    # Boost risk if high severity or very elevated temperature
    modifier = 0.0
    if severity and severity > 0.75:
        modifier += 0.08
    if temperature and temperature > 40.5:
        modifier += 0.06

    effective_confidence = confidence + modifier

    if effective_confidence >= threshold:
        return "high"
    if effective_confidence >= threshold - 0.20:
        return "medium"
    return "low"


def _build_reasoning(
    disease: str,
    confidence: float,
    feature_importance: dict[str, float],
    differential: list[dict],
    temperature: float | None,
    severity: float | None,
) -> str:
    display = DISEASE_DISPLAY[disease]
    pct = round(confidence * 100, 1)

    # Top 3 driving symptoms
    top_symptoms = list(feature_importance.keys())[:3]
    symptom_str = (
        ", ".join(s.replace("_", " ") for s in top_symptoms)
        if top_symptoms
        else "multiple clinical indicators"
    )

    # Second-best differential mention
    second_mention = ""
    if len(differential) > 1:
        runner_up = differential[1]
        if runner_up["score"] > 0.12:
            second_mention = (
                f" The closest differential is {DISEASE_DISPLAY[runner_up['disease']]} "
                f"({runner_up['percentage']}%) — "
                + (
                    f"consider ruling out via {', '.join(runner_up['matched_symptoms'][:2]).replace('_', ' ')}"
                    if runner_up["matched_symptoms"]
                    else "clinical overlap noted"
                )
                + "."
            )

    # Temperature and severity modifiers
    temp_str = (
        f" Elevated temperature ({temperature:.1f} °C) further supports this diagnosis."
        if temperature and temperature > 39.5
        else ""
    )
    sev_str = (
        f" High severity score ({severity:.0%}) suggests an advanced presentation requiring prompt attention."
        if severity and severity > 0.70
        else ""
    )

    confidence_qualifier = (
        "High" if confidence >= 0.75
        else "Moderate" if confidence >= 0.50
        else "Low"
    )

    return (
        f"{confidence_qualifier} confidence ({pct}%) for {display}. "
        f"Key clinical indicators: {symptom_str}."
        f"{temp_str}{sev_str}{second_mention} "
        f"Consult a qualified veterinarian for confirmatory diagnosis and treatment."
    )

"""
Bayesian symptom-based disease classifier.

P(disease | symptoms) ∝ P(symptoms | disease) × P(disease)

Uses log-space arithmetic to avoid floating-point underflow when many
symptoms are observed.  Returns the full posterior distribution plus
feature-importance (log-likelihood ratios) and a ranked differential.
"""

import math

from .disease_rules import (
    DISEASE_DISPLAY,
    DISEASE_PRIORS,
    DISEASES,
    SYMPTOM_LIKELIHOODS,
)

_EPSILON = 1e-9


def _temperature_is_elevated(temperature: float | None) -> bool:
    return temperature is not None and temperature > 39.5


def predict(
    symptoms: dict[str, bool | int],
    temperature: float | None = None,
    severity: float | None = None,
) -> dict:
    """
    Run Bayesian classification.

    Args:
        symptoms: dict of symptom_name → True/1 (present) or False/0 (absent).
                  Values may be int (0/1) or bool.
        temperature: rectal temperature in °C (optional).
        severity: overall severity 0–1 (optional, used downstream only).

    Returns:
        dict with keys:
          top_disease, confidence, probabilities,
          differential, feature_importance, active_symptoms
    """
    # Normalise symptom values to bool
    bool_symptoms: dict[str, bool] = {
        k: bool(v) for k, v in symptoms.items()
    }

    active_symptoms: set[str] = {k for k, v in bool_symptoms.items() if v}

    # Inject synthetic temperature symptom
    if _temperature_is_elevated(temperature):
        active_symptoms.add("temperature_elevated")
        bool_symptoms["temperature_elevated"] = True

    # ── Compute log-posterior ──────────────────────────────────────────────
    log_scores: dict[str, float] = {}
    for disease in DISEASES:
        likelihoods = SYMPTOM_LIKELIHOODS[disease]
        log_s = math.log(DISEASE_PRIORS[disease])

        for symptom, is_present in bool_symptoms.items():
            p_present = likelihoods.get(symptom, 0.02)
            p_absent = 1.0 - p_present
            if is_present:
                log_s += math.log(max(p_present, _EPSILON))
            else:
                log_s += math.log(max(p_absent, _EPSILON))

        log_scores[disease] = log_s

    # ── Softmax → probabilities ────────────────────────────────────────────
    max_log = max(log_scores.values())
    exp_scores = {d: math.exp(v - max_log) for d, v in log_scores.items()}
    total = sum(exp_scores.values()) or 1.0
    probabilities: dict[str, float] = {d: v / total for d, v in exp_scores.items()}

    # ── Top prediction ─────────────────────────────────────────────────────
    top_disease = max(probabilities, key=probabilities.__getitem__)
    confidence = probabilities[top_disease]

    # ── Feature importance (log-likelihood ratio) for top disease ─────────
    top_likelihoods = SYMPTOM_LIKELIHOODS[top_disease]
    feature_importance: dict[str, float] = {}
    for symptom, is_present in bool_symptoms.items():
        if not is_present:
            continue
        p = top_likelihoods.get(symptom, 0.02)
        llr = math.log(max(p, _EPSILON)) - math.log(max(1.0 - p, _EPSILON))
        if llr > 0:
            feature_importance[symptom] = round(llr, 4)

    fi_total = sum(feature_importance.values()) or 1.0
    feature_importance = {
        k: round(v / fi_total, 4)
        for k, v in sorted(feature_importance.items(), key=lambda x: x[1], reverse=True)
    }

    # ── Differential diagnosis ────────────────────────────────────────────
    differential = [
        {
            "disease": d,
            "display_name": DISEASE_DISPLAY[d],
            "score": round(probabilities[d], 4),
            "percentage": round(probabilities[d] * 100, 1),
            "matched_symptoms": [
                s for s in active_symptoms
                if SYMPTOM_LIKELIHOODS[d].get(s, 0.0) > 0.5
            ],
        }
        for d in sorted(probabilities, key=probabilities.__getitem__, reverse=True)
    ]

    return {
        "top_disease": top_disease,
        "confidence": round(confidence, 4),
        "probabilities": {d: round(v, 4) for d, v in probabilities.items()},
        "differential": differential,
        "feature_importance": feature_importance,
        "active_symptoms": sorted(active_symptoms),
    }

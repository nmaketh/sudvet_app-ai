import random
import uuid
from datetime import datetime, timedelta

from sqlalchemy import select

from app.core.config import settings
from app.core.security import get_password_hash
from app.db.session import SessionLocal
from app.ml.disease_rules import (
    DISEASE_DISPLAY,
    DISEASE_RECOMMENDATIONS,
    SYMPTOM_LIKELIHOODS,
)
from app.ml.explainer import explain
from app.ml.predictor import predict
from app.models.models import (
    Animal,
    Case,
    CaseStatus,
    ModelVersion,
    RiskLevel,
    TriageStatus,
    User,
    UserRole,
)

# ── Representative symptom profiles per disease ───────────────────────────────

_SYMPTOM_PROFILES: dict[str, dict[str, bool]] = {
    "lsd": {
        "skin_nodules": True, "painless_lumps": True,
        "enlarged_lymph_nodes": True, "fever": True,
        "loss_of_appetite": True, "depression": True,
        "mouth_blisters": False, "tongue_sores": False,
        "foot_lesions": False, "drooling": False,
        "lameness": False, "nasal_discharge": True,
        "eye_discharge": True, "difficulty_breathing": False,
        "coughing": False, "chest_pain_signs": False,
        "diarrhoea": False, "corneal_opacity": False,
        "swollen_lymph_nodes": False,
    },
    "fmd": {
        "mouth_blisters": True, "tongue_sores": True,
        "foot_lesions": True, "drooling": True,
        "lameness": True, "fever": True,
        "loss_of_appetite": True, "nasal_discharge": True,
        "skin_nodules": False, "painless_lumps": False,
        "enlarged_lymph_nodes": False, "swollen_lymph_nodes": False,
        "eye_discharge": False, "difficulty_breathing": False,
        "coughing": False, "chest_pain_signs": False,
        "diarrhoea": True, "corneal_opacity": False,
        "depression": True,
    },
    "ecf": {
        "fever": True, "swollen_lymph_nodes": True,
        "corneal_opacity": True, "loss_of_appetite": True,
        "depression": True, "nasal_discharge": True,
        "eye_discharge": True, "diarrhoea": True,
        "difficulty_breathing": True, "coughing": True,
        "skin_nodules": False, "painless_lumps": False,
        "enlarged_lymph_nodes": True, "mouth_blisters": False,
        "tongue_sores": False, "foot_lesions": False,
        "drooling": False, "lameness": True,
        "chest_pain_signs": False,
    },
    "cbpp": {
        "difficulty_breathing": True, "coughing": True,
        "chest_pain_signs": True, "fever": True,
        "nasal_discharge": True, "loss_of_appetite": True,
        "depression": True, "eye_discharge": False,
        "diarrhoea": False, "lameness": False,
        "skin_nodules": False, "painless_lumps": False,
        "enlarged_lymph_nodes": False, "swollen_lymph_nodes": True,
        "mouth_blisters": False, "tongue_sores": False,
        "foot_lesions": False, "drooling": False,
        "corneal_opacity": False,
    },
    "normal": {
        "fever": False, "loss_of_appetite": False,
        "skin_nodules": False, "painless_lumps": False,
        "enlarged_lymph_nodes": False, "swollen_lymph_nodes": False,
        "mouth_blisters": False, "tongue_sores": False,
        "foot_lesions": False, "drooling": False,
        "lameness": False, "nasal_discharge": False,
        "eye_discharge": False, "difficulty_breathing": False,
        "coughing": False, "chest_pain_signs": False,
        "diarrhoea": False, "corneal_opacity": False,
        "depression": False,
    },
}


def _jitter_symptoms(base_profile: dict[str, bool], noise: float = 0.15) -> dict[str, bool]:
    """Randomly flip a few symptoms to simulate realistic variation."""
    return {k: (not v if random.random() < noise else v) for k, v in base_profile.items()}


def _build_prediction_json(disease_key: str, temperature: float, severity: float) -> dict:
    """Run the real ML engine for a representative symptom profile."""
    symptoms = _jitter_symptoms(_SYMPTOM_PROFILES[disease_key])
    result = predict(symptoms=symptoms, temperature=temperature, severity=severity)
    explanation = explain(result, temperature=temperature, severity=severity)

    # Store as the canonical prediction_json format
    return {
        "label": explanation["label"],
        "display_label": explanation["display_label"],
        "confidence": explanation["confidence"],
        "method": explanation["method"],
        "risk_level": explanation["risk_level"],
        "differential": explanation["differential"],
        "feature_importance": explanation["feature_importance"],
        "rule_triggers": explanation["rule_triggers"],
        "reasoning": explanation["reasoning"],
        "recommendations": explanation["recommendations"],
        "probabilities": explanation["probabilities"],
        "temperature_note": explanation.get("temperature_note"),
        "severity_note": explanation.get("severity_note"),
        "gradcam_url": None,
    }


def seed_users(db):
    users_data = [
        {"name": "Admin User",  "email": "admin@cattle.ai", "role": UserRole.ADMIN, "location": "HQ"},
        {"name": "Dr. Amara Vet","email": "vet@cattle.ai",   "role": UserRole.VET,   "location": "District A"},
        {"name": "John CAHW",   "email": "cahw@cattle.ai",  "role": UserRole.CAHW,  "location": "Village 1"},
    ]
    created = []
    for row in users_data:
        exists = db.scalar(select(User).where(User.email == row["email"]))
        if exists:
            created.append(exists)
            continue
        user = User(
            name=row["name"],
            email=row["email"],
            role=row["role"],
            location=row["location"],
            password_hash=get_password_hash("Password123!"),
        )
        db.add(user)
        db.flush()
        created.append(user)
    return created


def seed_animals(db, owner_id: int):
    animals = []
    for i in range(1, 11):
        tag = f"AN-{1000 + i}"
        exists = db.scalar(select(Animal).where(Animal.tag == tag))
        if exists:
            animals.append(exists)
            continue
        animal = Animal(
            id=str(uuid.uuid4()),
            tag=tag,
            name=f"Cow {i}",
            owner_id=owner_id,
            location=f"Zone {((i - 1) % 3) + 1}",
        )
        db.add(animal)
        db.flush()
        animals.append(animal)
    return animals


def seed_cases(db, animals, cahw_id: int, vet_id: int):
    existing = db.scalar(select(Case.id).limit(1))
    if existing:
        return

    disease_keys = ["lsd", "fmd", "cbpp", "ecf", "normal"]
    statuses = [CaseStatus.open, CaseStatus.in_treatment, CaseStatus.resolved]
    triages = [TriageStatus.needs_review, TriageStatus.escalated]
    risk_map = {"high": RiskLevel.high, "medium": RiskLevel.medium, "low": RiskLevel.low}

    for i in range(25):
        disease_key = disease_keys[i % len(disease_keys)]
        temperature = round(random.uniform(38.0, 41.5), 1)
        severity = round(random.uniform(0.30, 0.95), 2)
        status = random.choice(statuses)
        created_at = datetime.utcnow() - timedelta(days=random.randint(0, 20))
        followup = created_at + timedelta(days=random.randint(1, 6)) if status == CaseStatus.resolved else None

        # Build rich prediction JSON using the real ML engine
        pred_json = _build_prediction_json(disease_key, temperature, severity)
        risk_str = pred_json.get("risk_level", "medium")
        risk_level = risk_map.get(risk_str, RiskLevel.medium)

        # Build realistic symptoms_json for the case
        base_symptoms = _SYMPTOM_PROFILES[disease_key]
        symptoms_json = {k: (1 if v else 0) for k, v in _jitter_symptoms(base_symptoms).items()}

        case = Case(
            id=str(uuid.uuid4()),
            client_case_id=f"CLI-{2000 + i}",
            animal_id=random.choice(animals).id,
            created_at=created_at,
            submitted_by_user_id=cahw_id,
            image_url=None,
            symptoms_json=symptoms_json,
            prediction_json=pred_json,
            method=pred_json["method"],
            confidence=pred_json["confidence"],
            risk_level=risk_level,
            status=status,
            triage_status=random.choice(triages),
            assigned_to_user_id=vet_id if i % 3 != 0 else None,
            followup_date=followup,
            notes="Seeded case — representative symptom profile." if i % 4 == 0 else None,
        )
        db.add(case)


def seed_models(db):
    if db.scalar(select(ModelVersion.id).limit(1)):
        return
    db.add_all([
        ModelVersion(type="symptom_bayesian", version="1.0.0", metrics_json={"accuracy": 0.87, "f1_macro": 0.84, "diseases": ["lsd","fmd","ecf","cbpp","normal"]}),
        ModelVersion(type="image_cnn",        version="0.1.0", metrics_json={"accuracy": 0.00, "note": "Pending — image model integration in progress"}),
        ModelVersion(type="hybrid",           version="0.1.0", metrics_json={"note": "Pending — combines symptom_bayesian + image_cnn"}),
    ])


def run_seed():
    db = SessionLocal()
    try:
        users = seed_users(db)
        admin, vet, cahw = users[0], users[1], users[2]
        animals = seed_animals(db, owner_id=cahw.id)
        seed_cases(db, animals, cahw_id=cahw.id, vet_id=vet.id)
        seed_models(db)
        db.commit()
        print("Seed complete:")
        print("  admin@cattle.ai  / Password123!  (ADMIN)")
        print("  vet@cattle.ai    / Password123!  (VET)")
        print("  cahw@cattle.ai   / Password123!  (CAHW)")
    finally:
        db.close()


if __name__ == "__main__":
    run_seed()

import uuid

from fastapi import APIRouter, Body, Depends, HTTPException, Query
from sqlalchemy import and_, or_, select
from sqlalchemy.orm import Session

from app.core.dependencies import get_current_user
from app.db.session import get_db
from app.models.models import Animal, Case, CaseStatus, User, UserRole
from app.schemas.animal import AnimalOut
from app.schemas.case import CaseOut


router = APIRouter(prefix="/animals", tags=["animals"])


def _case_out(item: Case) -> CaseOut:
    return CaseOut(
        id=item.id,
        client_case_id=item.client_case_id,
        animal_id=item.animal_id,
        animal_tag=item.animal.tag if item.animal else None,
        created_at=item.created_at,
        submitted_by_user_id=item.submitted_by_user_id,
        submitted_by_name=item.submitted_by.name if item.submitted_by else None,
        image_url=item.image_url,
        symptoms_json=item.symptoms_json or {},
        prediction_json=item.prediction_json or {},
        method=item.method,
        confidence=item.confidence,
        risk_level=item.risk_level,
        status=item.status,
        triage_status=item.triage_status,
        assigned_to_user_id=item.assigned_to_user_id,
        assigned_to_name=item.assigned_to.name if item.assigned_to else None,
        followup_date=item.followup_date,
        notes=item.notes,
        corrected_label=item.corrected_label,
    )


@router.get("", response_model=list[AnimalOut])
def list_animals(
    q: str | None = None,
    query_text: str | None = Query(default=None, alias="query"),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = select(Animal).order_by(Animal.created_at.desc())
    search = (q or query_text or "").strip()
    if search:
        text = f"%{search}%"
        query = query.where(or_(Animal.tag.ilike(text), Animal.name.ilike(text), Animal.location.ilike(text)))
    if current_user.role == UserRole.CAHW:
        query = query.where(Animal.owner_id == current_user.id)
    return db.scalars(query).all()


@router.get("/{animal_id}", response_model=AnimalOut)
def get_animal(animal_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal not found")
    if current_user.role == UserRole.CAHW and animal.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not allowed")
    return animal


@router.post("", response_model=AnimalOut, status_code=201)
def create_animal(
    body: dict = Body(default={}),
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Create an animal profile (Flutter field app compatibility)."""
    name = (body.get("name") or "").strip() or None
    location = (body.get("location") or current_user.location or "Field").strip() or "Field"

    # Accept optional tag from clients, otherwise generate a stable-looking field tag.
    raw_tag = (body.get("tag") or body.get("tag_id") or "").strip().upper()
    tag = raw_tag
    if not tag:
        for _ in range(5):
            candidate = f"COW-{uuid.uuid4().hex[:8].upper()}"
            exists = db.scalar(select(Animal).where(Animal.tag == candidate))
            if not exists:
                tag = candidate
                break
        if not tag:
            tag = f"COW-{uuid.uuid4().hex[:8].upper()}"

    if db.scalar(select(Animal).where(Animal.tag == tag)):
        raise HTTPException(status_code=409, detail="Animal tag already exists")

    animal = Animal(
        id=str(uuid.uuid4()),
        tag=tag,
        name=name,
        owner_id=current_user.id,
        location=location,
    )
    db.add(animal)
    db.commit()
    db.refresh(animal)
    return animal


@router.get("/{animal_id}/cases", response_model=list[CaseOut])
def animal_cases(animal_id: str, db: Session = Depends(get_db), current_user: User = Depends(get_current_user)):
    animal = db.get(Animal, animal_id)
    if not animal:
        raise HTTPException(status_code=404, detail="Animal not found")
    if current_user.role == UserRole.CAHW and animal.owner_id != current_user.id:
        raise HTTPException(status_code=403, detail="Not allowed")
    query = select(Case).where(Case.animal_id == animal_id)
    if current_user.role == UserRole.CAHW:
        query = query.where(Case.submitted_by_user_id == current_user.id)
    elif current_user.role == UserRole.VET:
        query = query.where(Case.assigned_to_user_id == current_user.id)
    elif current_user.role == UserRole.ADMIN:
        query = query.where(and_(Case.status == CaseStatus.open, Case.assigned_to_user_id.is_(None)))
    rows = db.scalars(query.order_by(Case.created_at.desc())).all()
    return [_case_out(item) for item in rows]

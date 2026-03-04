from datetime import datetime

from pydantic import BaseModel


class AnimalOut(BaseModel):
    id: str
    tag: str
    name: str | None
    owner_id: int
    location: str
    created_at: datetime

    class Config:
        from_attributes = True

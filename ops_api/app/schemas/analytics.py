from pydantic import BaseModel


class AnalyticsSummaryResponse(BaseModel):
    cases_by_disease: dict[str, int]
    cases_by_day: list[dict[str, int | str]]
    backlog_count: int
    avg_resolution_time: float
    high_risk_rate: float
    resolution_time_trend: list[dict[str, int | float | str]]
    backlog_trend: list[dict[str, int | str]]


class ModelOut(BaseModel):
    id: int
    type: str
    version: str
    metrics_json: dict
    updated_at: str


class ErrorLogOut(BaseModel):
    id: int
    source: str
    message: str
    created_at: str

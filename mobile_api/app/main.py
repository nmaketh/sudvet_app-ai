from __future__ import annotations

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .db import init_db
from .jobs import _start_job_worker, _stop_job_worker
from .routes import animals_router, auth_router, cases_router, core_router
from .settings import APP_TITLE, APP_VERSION, build_cors_origins

_cors_origins = build_cors_origins()

app = FastAPI(title=APP_TITLE, version=APP_VERSION)
app.add_middleware(
    CORSMiddleware,
    allow_origins=_cors_origins,
    allow_credentials=_cors_origins != ["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

@app.on_event("startup")
def startup() -> None:
    init_db()
    _start_job_worker()


@app.on_event("shutdown")
def shutdown() -> None:
    _stop_job_worker()

app.include_router(core_router)
app.include_router(auth_router)
app.include_router(animals_router)
app.include_router(cases_router)

import logging

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from slowapi import _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded

from app.api.routes import analytics, animals, auth, cases, predict, settings as dashboard_settings, system, users, vet
from app.core.config import settings
from app.core.limiter import limiter
from app.db.migrations import run_migrations
from app.db.session import SessionLocal
from app.models.models import Base, ErrorLog

logger = logging.getLogger(__name__)

app = FastAPI(title=settings.app_name)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)


@app.on_event("startup")
def on_startup():
    if (settings.app_env or "").lower() == "production":
        logger.info("Skipping metadata bootstrap in production; rely on Alembic migrations.")
        return

    from app.db.session import engine

    Base.metadata.create_all(bind=engine)
    with SessionLocal() as db:
        run_migrations(db)

origins = [origin.strip() for origin in settings.cors_origins.split(",") if origin.strip()]
# In development, allow localhost/127.0.0.1 on any port so Flutter web (random ports) can connect
# without requiring manual in-app server settings first.
allow_origin_regex = None
if (settings.app_env or "").lower() != "production":
    allow_origin_regex = r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$"

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins or ["http://localhost:3000"],
    allow_origin_regex=allow_origin_regex,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.middleware("http")
async def capture_errors(request: Request, call_next):
    def _record_error(message: str) -> None:
        db = SessionLocal()
        try:
            db.add(ErrorLog(source="api", message=message))
            db.commit()
        finally:
            db.close()

    try:
        response = await call_next(request)
        if response.status_code >= 500:
            _record_error(f"{request.method} {request.url.path} -> {response.status_code}")
        return response
    except Exception as exc:
        _record_error(f"Unhandled: {str(exc)}")
        return JSONResponse(status_code=500, content={"detail": "Internal server error"})


app.include_router(auth.router)
app.include_router(predict.router)
app.include_router(cases.router)
app.include_router(animals.router)
app.include_router(users.router)
app.include_router(analytics.router)
app.include_router(vet.router)
app.include_router(dashboard_settings.router)
app.include_router(system.router)


@app.get("/")
def root():
    return {"service": settings.app_name, "status": "ok"}


# Images are stored in Supabase Storage and served via public URLs.
# No local /uploads mount needed.

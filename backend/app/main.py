"""SCOPE backend API.

AI-Assisted Smoking Violation Reporting and Monitoring System.

Serves three consumers:
  - the Flutter mobile application (anonymous, unauthenticated)
  - the React administrative dashboard (authenticated, read-only over reports)
  - itself, for classification
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.routers import classify, geo, public, reports
from app.routers.admin import analytics, auth, infographics
from app.routers.admin import reports as admin_reports
from app.services import storage

settings = get_settings()
logger = logging.getLogger("scope")


@asynccontextmanager
async def lifespan(app: FastAPI):
    storage.ensure_directories()

    # Photographs staged by a reporter who abandoned the flow between S10 and
    # S12 may show identifiable individuals. Retaining them indefinitely would
    # be hard to defend under the PDPA Security Principle.
    purged = storage.purge_expired_staging()
    if purged:
        logger.info("Purged %d expired staging directories.", purged)

    logger.info(
        "AI classification: model=%s threshold=%.4f",
        settings.ai_model_version,
        settings.ai_confidence_threshold,
    )
    yield


app = FastAPI(
    title="SCOPE API",
    version="0.2.0",
    summary="AI-Assisted Smoking Violation Reporting and Monitoring System",
    description=(
        "Photographic evidence is classified **before** submission, so no "
        "unvalidated report ever reaches the database. Administrators hold "
        "read-only access: there is no endpoint anywhere in this API that "
        "verifies, approves, rejects or amends a filed report."
    ),
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=[settings.dashboard_origin],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Public reporting flow
app.include_router(classify.router)
app.include_router(reports.router)
app.include_router(public.router)
app.include_router(geo.router)

# Administrative dashboard
app.include_router(auth.router)
app.include_router(admin_reports.router)
app.include_router(analytics.router)
app.include_router(infographics.router)

# Stored photographs and infographic images.
# Development convenience only — a deployment should serve these from object
# storage behind signed URLs, since report photographs show identifiable
# individuals at identifiable premises.
storage.ensure_directories()
app.mount("/media", StaticFiles(directory=settings.upload_path), name="media")


@app.get("/health", tags=["System"], summary="Liveness probe")
def health() -> dict[str, str]:
    return {"status": "ok"}

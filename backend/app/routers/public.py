"""S02 / S04 / S06 — public content: infographics and the hotspot heatmap."""

from __future__ import annotations

import datetime as dt

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.models import Infographic, Report
from app.schemas import HotspotPoint, InfographicOut

router = APIRouter(prefix="/api/v1", tags=["Public content"])

# Roughly 110 m at the equator. Coarse enough that a point cannot be resolved
# to a single premise, fine enough that a heatmap still shows real structure.
_PUBLIC_PRECISION = 3


@router.get(
    "/infographics",
    response_model=list[InfographicOut],
    summary="The published awareness slots (S04 hub)",
)
def list_infographics(db: Session = Depends(get_db)) -> list[Infographic]:
    # Empty slots are left out, so S04 only ever sees complete infographics.
    return list(
        db.scalars(
            select(Infographic)
            .where(Infographic.image_path.is_not(None))
            .order_by(Infographic.infographic_id)
        ).all()
    )


@router.get(
    "/hotspots",
    response_model=list[HotspotPoint],
    summary="Public density heatmap (S06)",
)
def hotspots(
    days: int = Query(default=365, ge=1, le=3650),
    db: Session = Depends(get_db),
) -> list[HotspotPoint]:
    """Aggregated report density.

    Returns rounded coordinates with weights, never individual reports. The
    public map shows where violations concentrate; it never attributes a report
    to a named premise. That is a deliberate decision protecting both reporter
    safety and the system's defamation exposure, and it is why this endpoint
    exposes no reference number, premise name or timestamp.

    Officers get full precision on D03 instead — precision for enforcement,
    privacy for everyone else.
    """
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)

    rounded_lat = func.round(Report.latitude, _PUBLIC_PRECISION)
    rounded_lng = func.round(Report.longitude, _PUBLIC_PRECISION)

    rows = db.execute(
        select(rounded_lat, rounded_lng, func.count().label("weight"))
        .where(Report.submitted_at >= since)
        .group_by(rounded_lat, rounded_lng)
    ).all()

    return [
        HotspotPoint(latitude=float(lat), longitude=float(lng), weight=weight)
        for lat, lng, weight in rows
    ]

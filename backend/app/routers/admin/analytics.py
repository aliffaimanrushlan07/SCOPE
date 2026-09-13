"""D02 / D03 — analytics and hotspot clusters.

Deliberately absent from D02: average AI confidence, pending-review count and
verified count. All three described a verification workflow that no longer
exists, and reinstating any of them would reintroduce the contradiction the
revision removed.
"""

from __future__ import annotations

import datetime as dt
from typing import Literal

from fastapi import APIRouter, Depends, Query
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from app.database import get_db
from app.deps import get_current_admin
from app.models import AdminUser, Report
from app.schemas import ClusterOut, OverviewResponse, TimeSeriesPoint, TopLocation

router = APIRouter(prefix="/api/v1/admin", tags=["Admin — Analytics"])

# Section 10.4. Count is encoded three ways at once — size, colour and numeral
# — so the map stays readable for colour-blind users and survives black-and-
# white printing of the report. Lightness decreases monotonically across the
# scale, which is what makes that true.
_CLUSTER_BANDS = ((1, 4, 1), (5, 9, 2), (10, 19, 3), (20, None, 4))


@router.get(
    "/analytics/overview",
    response_model=OverviewResponse,
    summary="Overview panels (D02)",
)
def overview(
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
    days: int = Query(default=30, ge=1, le=3650),
    granularity: Literal["day", "week", "month"] = "day",
) -> OverviewResponse:
    now = dt.datetime.now(dt.timezone.utc)
    period_start = now - dt.timedelta(days=days)
    previous_start = period_start - dt.timedelta(days=days)

    total = db.scalar(select(func.count()).select_from(Report)) or 0

    period_total = (
        db.scalar(
            select(func.count())
            .select_from(Report)
            .where(Report.submitted_at >= period_start)
        )
        or 0
    )
    previous_total = (
        db.scalar(
            select(func.count())
            .select_from(Report)
            .where(
                Report.submitted_at >= previous_start,
                Report.submitted_at < period_start,
            )
        )
        or 0
    )

    percentage_change = None
    if previous_total:
        percentage_change = round(
            (period_total - previous_total) / previous_total * 100, 1
        )

    # Reports over time — supports patrol scheduling.
    bucket = func.date_trunc(granularity, Report.submitted_at).label("bucket")
    series = db.execute(
        select(bucket, func.count().label("count"))
        .where(Report.submitted_at >= period_start)
        .group_by(bucket)
        .order_by(bucket)
    ).all()

    # Top hotspot locations — the most actionable panel for enforcement.
    # Grouped by rounded coordinate rather than by premise name: the name is
    # optional free text supplied by an unidentified reporter, so it cannot
    # support reliable grouping. The coordinate can.
    rounded_lat = func.round(Report.latitude, 3).label("lat")
    rounded_lng = func.round(Report.longitude, 3).label("lng")
    locations = db.execute(
        select(
            rounded_lat,
            rounded_lng,
            func.count().label("count"),
            func.max(func.coalesce(Report.premise_name, Report.address_text)).label(
                "label"
            ),
        )
        .where(Report.submitted_at >= period_start)
        .group_by(rounded_lat, rounded_lng)
        .order_by(func.count().desc())
        .limit(10)
    ).all()

    return OverviewResponse(
        total_reports=total,
        period_total=period_total,
        previous_period_total=previous_total,
        percentage_change=percentage_change,
        reports_over_time=[
            TimeSeriesPoint(period=row.bucket.date(), count=row.count) for row in series
        ],
        top_locations=[
            TopLocation(
                label=row.label or f"{float(row.lat):.3f}, {float(row.lng):.3f}",
                count=row.count,
                latitude=float(row.lat),
                longitude=float(row.lng),
            )
            for row in locations
        ],
    )


@router.get(
    "/hotspots/clusters",
    response_model=list[ClusterOut],
    summary="Hotspot clusters (D03, FR09)",
)
def clusters(
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
    days: int = Query(default=365, ge=1, le=3650),
    precision: int = Query(default=3, ge=2, le=5),
) -> list[ClusterOut]:
    """Report clusters at full officer-facing precision.

    Note the deliberate difference from the public heatmap at /api/v1/hotspots:
    administrators get clusters resolvable to a location, the public gets
    density with no individual pins. Precision for enforcement, privacy for
    everyone else.
    """
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)

    lat = func.round(Report.latitude, precision).label("lat")
    lng = func.round(Report.longitude, precision).label("lng")

    rows = db.execute(
        select(lat, lng, func.count().label("count"))
        .where(Report.submitted_at >= since)
        .group_by(lat, lng)
        .order_by(func.count().desc())
    ).all()

    return [
        ClusterOut(
            latitude=float(row.lat),
            longitude=float(row.lng),
            count=row.count,
            band=_band_for(row.count),
        )
        for row in rows
    ]


def _band_for(count: int) -> int:
    for low, high, band in _CLUSTER_BANDS:
        if count >= low and (high is None or count <= high):
            return band
    return 1

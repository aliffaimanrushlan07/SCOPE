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
from app.schemas import (
    ClusterOut,
    OverviewResponse,
    TimeSeriesPoint,
    TimingCategory,
    TimingPeak,
    TimingResponse,
    TopLocation,
)

router = APIRouter(prefix="/api/v1/admin", tags=["Admin — Analytics"])

# Section 10.4. Count is encoded three ways at once — size, colour and numeral
# — so the map stays readable for colour-blind users and survives black-and-
# white printing of the report. Lightness decreases monotonically across the
# scale, which is what makes that true.
_CLUSTER_BANDS = ((1, 4, 1), (5, 9, 2), (10, 19, 3), (20, None, 4))

# Timestamps are stored in UTC, but the system serves Kuala Lumpur and
# Putrajaya. Every calendar bucket — a day, a week, an hour of the day — is
# taken in local time; otherwise a 12:30 lunchtime report lands in the
# 04:00–06:00 column and a Monday-morning week boundary falls at 08:00.
_LOCAL_TZ = "Asia/Kuala_Lumpur"

# Named time-of-day slots for the patrol-timing panel. Each spans whole
# two-hour blocks, so the category band lines up with the heatmap columns.
_TIME_CATEGORIES = (
    ("Late Night", 0, 4),
    ("Early Morning", 4, 6),
    ("Breakfast", 6, 10),
    ("Brunch", 10, 12),
    ("Lunch", 12, 14),
    ("Afternoon", 14, 16),
    ("Evening", 16, 20),
    ("Night", 20, 24),
)


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
    bucket = func.date_trunc(
        granularity, func.timezone(_LOCAL_TZ, Report.submitted_at)
    ).label("bucket")
    series = db.execute(
        select(bucket, func.count().label("count"))
        .where(Report.submitted_at >= period_start)
        .group_by(bucket)
        .order_by(bucket)
    ).all()

    # Top hotspot locations — the most actionable panel for enforcement.
    # Grouped by rounded coordinate rather than by premise name: the name is
    # optional free text supplied by an unidentified reporter, so it cannot
    # support reliable grouping. The coordinate can. The name only labels the
    # group, and the most common one does that best — an alphabetical max
    # would let one stray name at a neighbouring premise relabel the cell.
    rounded_lat = func.round(Report.latitude, 3).label("lat")
    rounded_lng = func.round(Report.longitude, 3).label("lng")
    locations = db.execute(
        select(
            rounded_lat,
            rounded_lng,
            func.count().label("count"),
            func.coalesce(
                func.mode().within_group(Report.premise_name),
                func.mode().within_group(Report.address_text),
            ).label("label"),
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
    "/analytics/timing",
    response_model=TimingResponse,
    summary="Patrol timing by day and time of day (D02)",
)
def timing(
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
    days: int = Query(default=30, ge=1, le=3650),
    lat: float | None = Query(default=None, ge=-90, le=90),
    lng: float | None = Query(default=None, ge=-180, le=180),
) -> TimingResponse:
    """When violations happen, for all locations or one hotspot.

    The period window is applied to ``submitted_at``, exactly as the overview
    does, so a location's total here matches its count in Top hotspot
    locations. The bucketing then uses ``reported_at`` — when the violation was
    photographed — because that, not when the reporter pressed submit, is what
    a patrol needs to be present for.

    ``lat``/``lng`` select one location by the same three-decimal grid (about
    110 m) that groups Top hotspot locations.
    """
    period_start = dt.datetime.now(dt.timezone.utc) - dt.timedelta(days=days)

    local = func.timezone(_LOCAL_TZ, Report.reported_at)
    day = (func.extract("isodow", local) - 1).label("day")
    block = func.floor(func.extract("hour", local) / 2).label("block")

    query = (
        select(day, block, func.count().label("count"))
        .where(Report.submitted_at >= period_start)
        .group_by(day, block)
    )
    if lat is not None and lng is not None:
        query = query.where(
            func.round(Report.latitude, 3) == round(lat, 3),
            func.round(Report.longitude, 3) == round(lng, 3),
        )

    grid = [[0] * 12 for _ in range(7)]
    for row in db.execute(query):
        grid[int(row.day)][int(row.block)] = row.count

    total = sum(map(sum, grid))
    by_day = [sum(row) for row in grid]
    by_block = [sum(grid[d][b] for d in range(7)) for b in range(12)]

    peak = None
    if total:
        count, d, b = max(
            (grid[d][b], -d, -b) for d in range(7) for b in range(12)
        )
        peak = TimingPeak(day=-d, block=-b, count=count)

    return TimingResponse(
        total=total,
        grid=grid,
        by_day=by_day,
        categories=[
            TimingCategory(
                label=label,
                start_hour=start,
                end_hour=end,
                count=sum(by_block[start // 2 : end // 2]),
            )
            for label, start, end in _TIME_CATEGORIES
        ],
        peak=peak,
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

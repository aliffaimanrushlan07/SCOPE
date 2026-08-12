"""D04 / D05 — report list, read-only detail, and CSV export.

Every route here is a GET. There is no PATCH, PUT or DELETE on report data
anywhere in this module, and that absence is the design: administrators view
and export, they never verify, approve, reject or amend. An examiner tracing
the API surface will find no write path from an officer to a report.
"""

from __future__ import annotations

import csv
import datetime as dt
import io
import math
import uuid
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query, Request, status
from fastapi.responses import StreamingResponse
from sqlalchemy import func, or_, select
from sqlalchemy.orm import Session, selectinload

from app.database import get_db
from app.deps import get_current_admin
from app.models import AIClassification, AdminUser, Report
from app.schemas import (
    AdminReportDetail,
    AdminReportRow,
    ClassificationOut,
    PaginatedReports,
    ReportPhotoOut,
)
from app.services import activity

router = APIRouter(prefix="/api/v1/admin/reports", tags=["Admin — Reports"])


def _filtered_query(
    search: str | None, date_from: dt.date | None, date_to: dt.date | None
):
    """Build the D04 filter.

    Search, date range. No status filter — no status exists. No violation type
    or premise type filter — neither field exists in the data model.
    """
    query = select(Report)

    if search:
        pattern = f"%{search.strip()}%"
        query = query.where(
            or_(
                Report.reference_no.ilike(pattern),
                Report.premise_name.ilike(pattern),
                Report.address_text.ilike(pattern),
            )
        )
    if date_from:
        query = query.where(Report.submitted_at >= _start_of_day(date_from))
    if date_to:
        query = query.where(Report.submitted_at < _start_of_day(date_to) + dt.timedelta(days=1))

    return query


@router.get("", response_model=PaginatedReports, summary="Report list (D04, FR10)")
def list_reports(
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
    search: str | None = Query(default=None, max_length=200),
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
    page: int = Query(default=1, ge=1),
    page_size: int = Query(default=25, ge=1, le=100),
) -> PaginatedReports:
    base = _filtered_query(search, date_from, date_to)

    total = db.scalar(select(func.count()).select_from(base.subquery())) or 0

    rows = db.execute(
        base.add_columns(AIClassification.highest_confidence)
        .join(AIClassification, AIClassification.report_id == Report.report_id)
        .order_by(Report.submitted_at.desc())
        .offset((page - 1) * page_size)
        .limit(page_size)
    ).all()

    return PaginatedReports(
        items=[
            AdminReportRow(
                report_id=report.report_id,
                reference_no=report.reference_no,
                submitted_at=report.submitted_at,
                premise_name=report.premise_name,
                address_text=report.address_text,
                ai_confidence=confidence,
            )
            for report, confidence in rows
        ],
        total=total,
        page=page,
        page_size=page_size,
        total_pages=math.ceil(total / page_size) if total else 0,
    )


@router.get("/export.csv", summary="CSV export (D04, FR13)")
def export_csv(
    request: Request,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
    search: str | None = Query(default=None, max_length=200),
    date_from: dt.date | None = None,
    date_to: dt.date | None = None,
) -> StreamingResponse:
    """Export the filtered set for patrol planning.

    The export is logged with its filter criteria. This data leaves the system,
    so recording which officer took it and what they took is the PDPA Security
    Principle expectation.
    """
    rows = db.execute(
        _filtered_query(search, date_from, date_to)
        .add_columns(
            AIClassification.highest_confidence,
            AIClassification.model_version,
            AIClassification.threshold_used,
        )
        .join(AIClassification, AIClassification.report_id == Report.report_id)
        .order_by(Report.submitted_at.desc())
    ).all()

    buffer = io.StringIO()
    writer = csv.writer(buffer)
    writer.writerow(
        [
            "Reference",
            "Submitted at",
            "Reported at",
            "Premise name",
            "Address",
            "Latitude",
            "Longitude",
            "AI confidence",
            "Model version",
            "Threshold",
            "Reporter",
        ]
    )
    for report, confidence, model_version, threshold in rows:
        writer.writerow(
            [
                report.reference_no,
                report.submitted_at.isoformat(),
                report.reported_at.isoformat(),
                report.premise_name or "",
                report.address_text or "",
                report.latitude,
                report.longitude,
                confidence,
                model_version,
                threshold,
                "Anonymous",
            ]
        )

    criteria = (
        f"search={search or '-'} from={date_from or '-'} "
        f"to={date_to or '-'} rows={len(rows)}"
    )
    activity.log(
        db, activity.EXPORT_CSV, admin_id=admin.admin_id, request=request, detail=criteria
    )
    db.commit()

    buffer.seek(0)
    filename = f"scope-reports-{dt.date.today().isoformat()}.csv"
    return StreamingResponse(
        iter([buffer.getvalue()]),
        media_type="text/csv",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.get(
    "/{report_id}",
    response_model=AdminReportDetail,
    summary="Read-only report detail (D05, FR11)",
)
def report_detail(
    report_id: uuid.UUID,
    request: Request,
    db: Session = Depends(get_db),
    admin: AdminUser = Depends(get_current_admin),
) -> AdminReportDetail:
    report = db.scalar(
        select(Report)
        .options(selectinload(Report.photos), selectinload(Report.classification))
        .where(Report.report_id == report_id)
    )
    if report is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Report not found."
        )

    activity.log(
        db,
        activity.VIEW_REPORT,
        admin_id=admin.admin_id,
        report_id=report.report_id,
        request=request,
    )

    integrity_metres = _haversine_metres(
        report.capture_latitude,
        report.capture_longitude,
        report.latitude,
        report.longitude,
    )

    db.commit()

    return AdminReportDetail(
        report_id=report.report_id,
        reference_no=report.reference_no,
        reported_at=report.reported_at,
        submitted_at=report.submitted_at,
        latitude=report.latitude,
        longitude=report.longitude,
        capture_latitude=report.capture_latitude,
        capture_longitude=report.capture_longitude,
        premise_name=report.premise_name,
        address_text=report.address_text,
        photos=[ReportPhotoOut.model_validate(p) for p in report.photos],
        classification=(
            ClassificationOut.model_validate(report.classification)
            if report.classification
            else None
        ),
        location_integrity_metres=integrity_metres,
    )


def _start_of_day(value: dt.date) -> dt.datetime:
    return dt.datetime.combine(value, dt.time.min, tzinfo=dt.timezone.utc)


def _haversine_metres(
    lat1: Decimal | None,
    lng1: Decimal | None,
    lat2: Decimal | None,
    lng2: Decimal | None,
) -> float | None:
    """Distance between the capture position (S08) and the tagged position (S11).

    A large divergence means the photograph was taken somewhere other than the
    place the reporter tagged, which is worth an officer's attention. Computed
    here rather than in PostGIS because it is one pair of points on an already
    loaded row — a round trip to the database would buy nothing.
    """
    if None in (lat1, lng1, lat2, lng2):
        return None

    radius = 6_371_000.0
    p1, p2 = math.radians(float(lat1)), math.radians(float(lat2))
    delta_lat = math.radians(float(lat2) - float(lat1))
    delta_lng = math.radians(float(lng2) - float(lng1))

    a = (
        math.sin(delta_lat / 2) ** 2
        + math.cos(p1) * math.cos(p2) * math.sin(delta_lng / 2) ** 2
    )
    return round(2 * radius * math.asin(math.sqrt(a)), 1)

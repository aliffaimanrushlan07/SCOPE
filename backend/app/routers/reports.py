"""S12 / S13 / S14 — report submission and device-bound history."""

from __future__ import annotations

import datetime as dt
import uuid

from fastapi import APIRouter, Depends, Header, HTTPException, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session, selectinload

from app.config import get_settings
from app.database import get_db
from app.models import AIClassification, Report, ReportPhoto
from app.schemas import (
    ReportCreate,
    ReportCreateResponse,
    ReportDetail,
    ReportHistoryItem,
    ReportPhotoOut,
)
from app.services import storage
from app.services.reference import generate_reference_no

router = APIRouter(prefix="/api/v1/reports", tags=["Reporting"])
settings = get_settings()


@router.post(
    "",
    response_model=ReportCreateResponse,
    status_code=status.HTTP_201_CREATED,
    summary="Submit a report (S12 -> S13)",
)
def create_report(
    payload: ReportCreate,
    db: Session = Depends(get_db),
    idempotency_key: str | None = Header(default=None, alias="Idempotency-Key"),
) -> ReportCreateResponse:
    # --- Duplicate submit (section 7) ---------------------------------------
    # The validation token is single-use, so a receipt left by an earlier
    # submission is itself the idempotency record.
    receipt = storage.read_receipt(payload.validation_token)
    if receipt is not None:
        report = db.scalar(
            select(Report).where(Report.reference_no == receipt["reference_no"])
        )
        if report is not None:
            return ReportCreateResponse(
                reference_no=report.reference_no,
                submitted_at=report.submitted_at,
                photos_stored=len(report.photos),
                duplicate_submission=True,
            )

    # --- The server's own record of the classification ----------------------
    verdict = storage.read_verdict(payload.validation_token)
    if verdict is None:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                "Validation token is unknown or has expired. Please validate the "
                "photo evidence again."
            ),
        )

    if verdict["outcome"] != "PASS":
        # Unreachable through the app, which routes a FAIL back to S08. Guarded
        # anyway: a report whose evidence did not clear the threshold must never
        # be persisted.
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This evidence did not pass validation and cannot be submitted.",
        )

    passing = [p for p in verdict["photos"] if p["passed"]]
    if not passing:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="No photograph cleared the confidence threshold.",
        )

    # --- Rate limiting (section S14) ----------------------------------------
    # Replaces the account-level deterrence that anonymous reporting gives up.
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(hours=1)
    recent = db.scalar(
        select(func.count())
        .select_from(Report)
        .where(Report.device_id == payload.device_id, Report.submitted_at >= since)
    )
    if recent is not None and recent >= settings.rate_limit_per_device_per_hour:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=(
                "You have submitted several reports recently. Please try again "
                "later."
            ),
        )

    # --- Persist: report, photographs and classification in one transaction --
    report_id = uuid.uuid4()
    stored_paths: list[str] = []

    try:
        stored_paths = storage.promote_photos(
            payload.validation_token,
            report_id,
            [p["staged_filename"] for p in passing],
        )

        report = Report(
            report_id=report_id,
            reference_no=generate_reference_no(db),
            device_id=payload.device_id,
            premise_name=payload.premise_name,
            address_text=payload.address_text,
            latitude=payload.latitude,
            longitude=payload.longitude,
            capture_latitude=payload.capture_latitude,
            capture_longitude=payload.capture_longitude,
            reported_at=payload.reported_at,
        )
        db.add(report)

        for sequence_no, (photo, path) in enumerate(
            zip(passing, stored_paths, strict=True), start=1
        ):
            db.add(
                ReportPhoto(
                    report_id=report_id,
                    sequence_no=sequence_no,
                    storage_path=path,
                    captured_at=payload.reported_at,
                    confidence_score=photo["confidence"],
                    is_validated=True,
                )
            )

        db.add(
            AIClassification(
                report_id=report_id,
                model_version=verdict["model_version"],
                threshold_used=verdict["threshold_used"],
                outcome="PASS",
                highest_confidence=verdict["highest_confidence"],
                photos_evaluated=verdict["photos_evaluated"],
                photos_passed=verdict["photos_passed"],
                evaluated_at=dt.datetime.fromisoformat(verdict["evaluated_at"]),
            )
        )

        db.commit()
    except Exception:
        db.rollback()
        storage.discard_report_photos(report_id)
        raise

    db.refresh(report)
    storage.write_receipt(payload.validation_token, report.reference_no, str(report_id))

    return ReportCreateResponse(
        reference_no=report.reference_no,
        submitted_at=report.submitted_at,
        photos_stored=len(stored_paths),
        duplicate_submission=False,
    )


@router.get(
    "/device/{device_id}",
    response_model=list[ReportHistoryItem],
    summary="Report History for one device (S14)",
)
def report_history(
    device_id: str, db: Session = Depends(get_db)
) -> list[ReportHistoryItem]:
    """Reports filed from this handset, newest first.

    A receipt log, not a tracker — no status is returned, because nothing in
    the system can change a report after it is filed. History is bound to the
    device identifier and does not survive a reinstall; the app states this
    plainly rather than letting a user read it as a bug.
    """
    reports = db.scalars(
        select(Report)
        .options(selectinload(Report.photos))
        .where(Report.device_id == device_id)
        .order_by(Report.submitted_at.desc())
    ).all()

    return [_to_history_item(r) for r in reports]


@router.get(
    "/{reference_no}",
    response_model=ReportDetail,
    summary="Read-only report detail (S14)",
)
def report_detail(
    reference_no: str,
    device_id: str,
    db: Session = Depends(get_db),
) -> ReportDetail:
    """Detail of one report.

    ``device_id`` is required and must match the filing device. Without it, a
    guessed reference number would expose someone else's photographic evidence.
    """
    report = db.scalar(
        select(Report)
        .options(selectinload(Report.photos))
        .where(Report.reference_no == reference_no, Report.device_id == device_id)
    )
    if report is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail="Report not found."
        )

    base = _to_history_item(report)
    return ReportDetail(
        **base.model_dump(),
        latitude=report.latitude,
        longitude=report.longitude,
        photos=[ReportPhotoOut.model_validate(p) for p in report.photos],
    )


def _to_history_item(report: Report) -> ReportHistoryItem:
    photos = sorted(report.photos, key=lambda p: p.sequence_no)
    return ReportHistoryItem(
        reference_no=report.reference_no,
        premise_name=report.premise_name,
        address_text=report.address_text,
        reported_at=report.reported_at,
        submitted_at=report.submitted_at,
        photo_count=len(photos),
        thumbnail_path=photos[0].storage_path if photos else None,
    )

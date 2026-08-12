"""S10 — AI photo evidence validation.

This endpoint writes NOTHING to the database. Classification precedes
persistence: a photograph that fails is discarded and never enters the data
store, so no invalid report can reach an administrator. That ordering is the
structural expression of the design decision that the model is the sole and
final arbiter of evidential validity (DFD process 2.0 -> 3.0).
"""

from __future__ import annotations

from fastapi import APIRouter, File, HTTPException, UploadFile, status

from app.config import get_settings
from app.schemas import ClassifyResponse, PhotoVerdict
from app.services import inference, storage

router = APIRouter(prefix="/api/v1", tags=["Reporting"])
settings = get_settings()

_ALLOWED_CONTENT_TYPES = {"image/jpeg", "image/jpg", "image/png", "image/webp"}


@router.post(
    "/classify",
    response_model=ClassifyResponse,
    summary="Validate photo evidence (S10)",
)
async def classify(photos: list[UploadFile] = File(...)) -> ClassifyResponse:
    if not 1 <= len(photos) <= settings.max_photos_per_report:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=(
                f"Between 1 and {settings.max_photos_per_report} photographs are "
                f"required; {len(photos)} were submitted."
            ),
        )

    storage.ensure_directories()
    token, staging_dir = storage.create_staging_dir()

    images: list[tuple[str, str, bytes]] = []
    for index, upload in enumerate(photos, start=1):
        if upload.content_type not in _ALLOWED_CONTENT_TYPES:
            raise HTTPException(
                status_code=status.HTTP_415_UNSUPPORTED_MEDIA_TYPE,
                detail=f"Unsupported image type: {upload.content_type}.",
            )

        data = await upload.read()
        if not data:
            raise HTTPException(
                status_code=status.HTTP_400_BAD_REQUEST,
                detail=f"Photograph {index} is empty.",
            )
        if len(data) > settings.max_photo_bytes:
            raise HTTPException(
                status_code=status.HTTP_413_REQUEST_ENTITY_TOO_LARGE,
                detail=(
                    f"Photograph {index} exceeds the "
                    f"{settings.max_photo_bytes // (1024 * 1024)} MB limit."
                ),
            )

        suffix = _suffix_for(upload.content_type)
        staged = storage.stage_photo(staging_dir, index, data, suffix)
        images.append((upload.filename or f"photo-{index}", staged.name, data))

    result = inference.classify_photos(images)

    # Record the server's own verdict. POST /reports reads it back from here
    # rather than trusting scores supplied by the client.
    storage.write_verdict(
        staging_dir,
        {
            "outcome": result.outcome,
            "model_version": result.model_version,
            "threshold_used": result.threshold_used,
            "highest_confidence": result.highest_confidence,
            "photos_evaluated": result.photos_evaluated,
            "photos_passed": result.photos_passed,
            "evaluated_at": result.evaluated_at.isoformat(),
            "photos": [
                {
                    "index": p.index,
                    "filename": p.filename,
                    "staged_filename": p.staged_filename,
                    "confidence": p.confidence,
                    "passed": p.passed,
                    "reason": p.reason,
                }
                for p in result.photos
            ],
        },
    )

    return ClassifyResponse(
        validation_token=token,
        outcome=result.outcome,
        model_version=result.model_version,
        threshold_used=result.threshold_used,
        highest_confidence=result.highest_confidence,
        photos_evaluated=result.photos_evaluated,
        photos_passed=result.photos_passed,
        evaluated_at=result.evaluated_at,
        photos=[
            PhotoVerdict(
                index=p.index,
                filename=p.filename,
                confidence=p.confidence,
                passed=p.passed,
                reason=p.reason,
            )
            for p in result.photos
        ],
    )


def _suffix_for(content_type: str | None) -> str:
    return {
        "image/jpeg": ".jpg",
        "image/jpg": ".jpg",
        "image/png": ".png",
        "image/webp": ".webp",
    }.get(content_type or "", ".jpg")
